// Build the distro-native desktop, Debian package, and matching sources.
import 'dart:convert';
import 'dart:io';

import 'package_linux.dart';
import 'package_release.dart';

Future<void> main(List<String> args) async {
  try {
    final outputPath = switch (args) {
      ['--output', final String path] when !path.startsWith('--') => path,
      _ => throw const FormatException(
        'Usage: dart tool/package_deb.dart --output DIRECTORY',
      ),
    };
    final root = File.fromUri(Platform.script).parent.parent;
    final os = await File('/etc/os-release').readAsString();
    if (!RegExp(r'^ID=ubuntu$', multiLine: true).hasMatch(os) ||
        !RegExp(r'^VERSION_ID="22\.04"$', multiLine: true).hasMatch(os)) {
      throw StateError(
        'Build Debian packages in the Ubuntu 22.04 builder; see docs/debian.md.',
      );
    }
    final output = Directory(outputPath).absolute;
    if (output.existsSync()) {
      throw StateError('Output already exists: ${output.path}');
    }
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(await File('${root.path}/pubspec.yaml').readAsString())!
        .group(1)!;
    final packageVersion = debianVersion(version);
    final (bundle: bundle, stamp: built) = await buildLinuxRelease(
      root,
      portableControl: true,
    );
    final scratch = await Directory.systemTemp.createTemp('legion-deb-');
    try {
      final staging = Directory('${scratch.path}/package');
      await stageDesktopPackage(root, bundle, staging);
      await File(
        '${root.path}/packaging/debian/legion_frontend',
      ).copy('${staging.path}/launcher');
      await runPackagingCommand('install', [
        '-Dm755',
        '${staging.path}/launcher',
        '${staging.path}/usr/bin/legion_frontend',
      ]);
      await File('${staging.path}/launcher').delete();
      await runPackagingCommand('desktop-file-validate', [
        '${staging.path}/usr/share/applications/$appId.desktop',
      ]);
      await runPackagingCommand('appstreamcli', [
        'validate',
        '--no-net',
        '${staging.path}/usr/share/metainfo/$appId.metainfo.xml',
      ]);
      if (jsonEncode(await inventoryReleaseTree(bundle)) !=
          jsonEncode(built['bundle'])) {
        throw StateError(
          'The built bundle changed while staging; build again.',
        );
      }
      final elf = await inspectDesktopPackage(staging);
      final appBundle = Directory('${staging.path}/usr/lib/legion_frontend');
      final stamp = await recordReleaseBuild(
        appBundle,
        (built['inputs'] as Map).cast<String, Object>(),
        portableControl: true,
      );
      final dependencies = await debianDependencies(staging, elf.keys);
      final doc = Directory(
        '${staging.path}/usr/share/doc/legion-linux-frontend',
      )..createSync(recursive: true);
      await File('${root.path}/LICENSE').copy('${doc.path}/copyright');
      await File('${root.path}/docs/debian.md').copy('${doc.path}/README.md');
      final control = Directory('${staging.path}/DEBIAN')..createSync();
      final size = (await runPackagingCommand('du', [
        '-sk',
        '${staging.path}/usr',
      ])).split(RegExp(r'\s+')).first;
      await File('${control.path}/control').writeAsString(
        '''Package: legion-linux-frontend
Version: $packageVersion
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Prn-Ice <Prn-Ice@users.noreply.github.com>
Homepage: https://github.com/Prn-Ice/LenovoLegionLinuxFrontend
Installed-Size: $size
Depends: $dependencies
Description: Lenovo Legion hardware frontend
 Desktop controls for supported Lenovo Legion laptops. Temporary hardware
 access requires the separately installed driver, legion_cli, and a desktop
 authentication agent. Installed service mode remains the default.
''',
      );
      await output.create(recursive: true);
      final fixtureDirectory = '${root.path}/build/deb-fixtures';
      await runPackagingCommand('cmake', [
        '-S',
        '${root.path}/control/test',
        '-B',
        fixtureDirectory,
        '-G',
        'Ninja',
        '-DCMAKE_BUILD_TYPE=Release',
      ]);
      await runPackagingCommand('cmake', [
        '--build',
        fixtureDirectory,
        '--parallel',
        '2',
        '--target',
        'legion_cli',
        'legion-portable-test-client',
      ]);
      final fixtures = File('${output.path}/vm-fixtures.tar.gz');
      await runPackagingCommand('tar', [
        '-czf',
        fixtures.path,
        '-C',
        fixtureDirectory,
        'legion_cli',
        'legion-portable-test-client',
      ]);
      final prefix = 'legion-frontend-$version-amd64';
      final deb = File(
        '${output.path}/legion-linux-frontend_${packageVersion}_amd64.deb',
      );
      final payload = await inventoryReleaseTree(
        Directory('${staging.path}/usr'),
      );
      await runPackagingCommand('dpkg-deb', [
        '--root-owner-group',
        '--build',
        staging.path,
        deb.path,
      ]);
      if (jsonEncode(
            await inventoryReleaseTree(Directory('${staging.path}/usr')),
          ) !=
          jsonEncode(payload)) {
        throw StateError(
          'The Debian payload changed during packaging; build again.',
        );
      }
      final source = File('${output.path}/$prefix-source.tar.gz');
      await packageReleaseSource(root, appBundle, source, stamp);
      final manifest = <String, Object>{
        'format': 1,
        'version': version,
        'package_version': packageVersion,
        'source_commit': (built['inputs'] as Map)['commit']!,
        'architecture': 'amd64',
        'build_os': os,
        'portable_control': true,
        'default_control_mode': 'installedService',
        'depends': dependencies,
        'vm_fixtures_sha256': await fileSha256(fixtures),
        'elf_dependencies': elf,
        'bundle': stamp['bundle']!,
        'payload': payload,
        'files': {
          deb.uri.pathSegments.last: await fileSha256(deb),
          source.uri.pathSegments.last: await fileSha256(source),
        },
        'qualification': {
          'hardware': 'unverified',
          'desktop_authentication': 'unverified',
        },
      };
      final metadata = File('${output.path}/$prefix.json');
      await metadata.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
      );
      await File('${output.path}/SHA256SUMS').writeAsString(
        '${(await Future.wait([deb, source, metadata].map((file) async => '${await fileSha256(file)}  ${file.uri.pathSegments.last}'))).join('\n')}\n',
      );
      stdout.writeln('Packaged Debian frontend and source: ${output.path}');
    } finally {
      await scratch.delete(recursive: true);
    }
  } catch (error) {
    stderr.writeln('Debian package: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}

String debianVersion(String version) {
  final match = RegExp(
    r'^(\d+\.\d+\.\d+)(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.]+))?$',
  ).firstMatch(version);
  if (match == null) {
    throw FormatException('Unsupported release version: $version');
  }
  return '${match[1]}${match[2] == null ? '' : '~${match[2]}'}${match[3] == null ? '' : '+${match[3]}'}-1';
}

Future<String> debianDependencies(
  Directory staging,
  Iterable<String> executables,
) async {
  // Mark only shipped libraries as private. Missing system-library metadata
  // remains an error in dpkg-shlibdeps.
  final debian = Directory('${staging.path}/debian')..createSync();
  await File('${debian.path}/control').writeAsString(
    'Source: legion-linux-frontend\n\nPackage: legion-linux-frontend\nArchitecture: amd64\nDescription: Legion frontend\n',
  );
  final result = await Process.run(
    'dpkg-shlibdeps',
    [
      '-O',
      '-l${staging.path}/usr/lib/legion_frontend/lib',
      '-S${staging.path}',
      '-xlegion-linux-frontend',
      for (final path in executables)
        '-e${staging.path}/${path.replaceFirst(RegExp(r'^\./'), '')}',
    ],
    workingDirectory: staging.path,
    environment: {'LC_ALL': 'C'},
  );
  if (result.exitCode != 0) {
    throw StateError('dpkg-shlibdeps failed: ${result.stderr}');
  }
  final generated = (result.stdout as String).trim().replaceFirst(
    'shlibs:Depends=',
    '',
  );
  if (generated.isEmpty) {
    throw StateError('dpkg-shlibdeps returned no dependencies.');
  }
  await debian.delete(recursive: true);
  return '$generated, libegl1, libgles2, gsettings-desktop-schemas, xdg-user-dirs, polkitd | policykit-1, systemd';
}
