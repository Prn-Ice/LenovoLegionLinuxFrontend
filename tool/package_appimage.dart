// Build the Ubuntu desktop bundle, source companion, and type-2 AppImage.
import 'dart:convert';
import 'dart:io';

import 'package_release.dart';

const appId = 'io.github.prnice.legion_linux_frontend';

Future<void> main(List<String> args) async {
  try {
    final (inputPath, outputPath) = switch (args) {
      ['--runtime-inputs', final String inputs, '--output', final String output]
          when !inputs.startsWith('--') && !output.startsWith('--') =>
        (inputs, output),
      _ => throw const FormatException(
        'Usage: dart tool/package_appimage.dart --runtime-inputs DIRECTORY --output DIRECTORY',
      ),
    };
    final root = File.fromUri(Platform.script).parent.parent;
    final os = await File('/etc/os-release').readAsString();
    if (!RegExp(r'^ID=ubuntu$', multiLine: true).hasMatch(os) ||
        !RegExp(r'^VERSION_ID="22\.04"$', multiLine: true).hasMatch(os)) {
      throw StateError(
        'Build AppImages in the Ubuntu 22.04 builder; see docs/appimage.md.',
      );
    }
    final output = Directory(outputPath).absolute;
    if (output.existsSync()) {
      throw StateError('Output already exists: ${output.path}');
    }
    final inputs = Directory(inputPath).absolute;
    await verifyRuntimeInputs(root, inputs);
    final (bundle: bundle, stamp: built) = await buildLinuxRelease(
      root,
      portableControl: true,
    );
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(await File('${root.path}/pubspec.yaml').readAsString())!
        .group(1)!;
    if (!RegExp(r'^\d+\.\d+\.\d+(?:[-+][a-zA-Z0-9.+-]+)?$').hasMatch(version)) {
      throw StateError(
        'The application version cannot be used in an artifact filename.',
      );
    }
    final scratch = await Directory.systemTemp.createTemp('legion-appimage-');
    try {
      final appdir = Directory('${scratch.path}/Legion.AppDir');
      await stageAppDir(root, bundle, appdir, runtimeInputs: inputs);
      await runPackagingCommand('desktop-file-validate', [
        '${appdir.path}/$appId.desktop',
      ]);
      await runPackagingCommand('appstreamcli', [
        'validate',
        '--no-net',
        '${appdir.path}/usr/share/metainfo/$appId.metainfo.xml',
      ]);
      // A library or helper changed while staging must invalidate the build.
      if (jsonEncode(await inventoryReleaseTree(bundle)) !=
          jsonEncode(built['bundle'])) {
        throw StateError(
          'The built bundle changed while staging; build again.',
        );
      }
      final elf = await inspectAppDir(appdir);
      final appBundle = Directory('${appdir.path}/usr/lib/legion_frontend');
      final stamp = await recordReleaseBuild(
        appBundle,
        (built['inputs'] as Map).cast<String, Object>(),
        portableControl: true,
      );
      await output.create(recursive: true);
      final name = 'legion-frontend-$version-x86_64';
      final source = File('${output.path}/$name-source.tar.gz');
      await packageReleaseSource(
        root,
        appBundle,
        source,
        stamp,
        additionalSources: inputs,
      );
      await verifyRuntimeInputs(root, inputs);
      final squashfs = '${scratch.path}/payload.squashfs';
      await runPackagingCommand('mksquashfs', [
        appdir.path,
        squashfs,
        '-noappend',
        '-root-owned',
        '-comp',
        'gzip',
        '-mkfs-time',
        '0',
        '-all-time',
        '0',
        '-processors',
        '2',
        '-no-progress',
      ]);
      final image = File('${output.path}/$name.AppImage');
      final sink = image.openWrite();
      await sink.addStream(File('${inputs.path}/runtime-x86_64').openRead());
      await sink.addStream(File(squashfs).openRead());
      await sink.close();
      await runPackagingCommand('chmod', ['755', image.path]);
      final manifest = <String, Object>{
        'format': 1,
        'version': version,
        'source_commit': (built['inputs'] as Map)['commit'],
        'architecture': 'x86_64',
        'build_os': os,
        'portable_control': true,
        'default_control_mode': 'installedService',
        'elf_dependencies': elf,
        'appdir': await inventoryReleaseTree(appdir),
        'runtime': jsonDecode(
          await File(
            '${root.path}/packaging/appimage/build-inputs.json',
          ).readAsString(),
        ),
        'files': {
          image.uri.pathSegments.last: await fileSha256(image),
          source.uri.pathSegments.last: await fileSha256(source),
        },
        'qualification': {
          'desktop_authentication': 'unverified',
          'hardware': 'unverified',
        },
      };
      final manifestFile = File('${output.path}/$name.json');
      await manifestFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
      );
      final checksums = [image, source, manifestFile];
      await File('${output.path}/SHA256SUMS').writeAsString(
        '${(await Future.wait(checksums.map((file) async => '${await fileSha256(file)}  ${file.uri.pathSegments.last}'))).join('\n')}\n',
      );
      stdout.writeln('Packaged AppImage and source: ${output.path}');
    } finally {
      await scratch.delete(recursive: true);
    }
  } catch (error) {
    stderr.writeln('AppImage: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}

/// Copy the Flutter layout beside its helper and omit installed-service files.
Future<void> stageAppDir(
  Directory root,
  Directory bundle,
  Directory appdir, {
  required Directory runtimeInputs,
}) async {
  if (appdir.existsSync()) throw StateError('AppDir already exists.');
  final appBundle = Directory('${appdir.path}/usr/lib/legion_frontend');
  await appBundle.create(recursive: true);
  await runPackagingCommand('cp', ['-a', '${bundle.path}/.', appBundle.path]);
  for (final path in [
    'lib/systemd',
    'lib/sysusers.d',
    'share/dbus-1',
    'share/polkit-1',
  ]) {
    final directory = Directory('${appBundle.path}/$path');
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
  for (final name in ['legion-telemetry-service', 'legion-control-service']) {
    final file = File('${appBundle.path}/libexec/$name');
    if (file.existsSync()) await file.delete();
  }
  if (!File('${appBundle.path}/libexec/legion-portable-control').existsSync()) {
    throw StateError('The desktop bundle has no portable helper.');
  }
  final packaging = '${root.path}/packaging/appimage';
  await File('$packaging/AppRun').copy('${appdir.path}/AppRun');
  await runPackagingCommand('chmod', ['755', '${appdir.path}/AppRun']);
  await File('$packaging/$appId.desktop').copy('${appdir.path}/$appId.desktop');
  await File(
    '${root.path}/assets/branding/legion_mark.svg',
  ).copy('${appdir.path}/$appId.svg');
  for (final entry in {
    'applications/$appId.desktop': '$packaging/$appId.desktop',
    'metainfo/$appId.metainfo.xml': '$packaging/$appId.metainfo.xml',
    'icons/hicolor/scalable/apps/$appId.svg':
        '${root.path}/assets/branding/legion_mark.svg',
    'licenses/legion_frontend/branding/README.md':
        '${root.path}/assets/branding/README.md',
  }.entries) {
    final target = File('${appdir.path}/usr/share/${entry.key}');
    await target.parent.create(recursive: true);
    await File(entry.value).copy(target.path);
  }
  final specification =
      jsonDecode(await File('$packaging/build-inputs.json').readAsString())
          as Map;
  for (final item in (specification['runtime_sources'] as List).cast<Map>()) {
    final license = await runPackagingCommand('tar', [
      '-xOf',
      '${runtimeInputs.path}/${item['file']}',
      item['license'] as String,
      ...(item['additional_licenses'] as List? ?? []).cast<String>(),
    ]);
    final target = File(
      '${appdir.path}/usr/share/licenses/appimage-runtime/${item['name']}.txt',
    );
    await target.parent.create(recursive: true);
    await target.writeAsString(license);
  }
}

Future<void> verifyRuntimeInputs(Directory root, Directory inputs) async {
  final specification =
      jsonDecode(
            await File(
              '${root.path}/packaging/appimage/build-inputs.json',
            ).readAsString(),
          )
          as Map;
  for (final item in [
    specification['runtime'],
    ...specification['runtime_sources'] as List,
  ].cast<Map>()) {
    final file = File('${inputs.path}/${item['file']}');
    if (await fileSha256(file) != item['sha256']) {
      throw StateError(
        'Release input checksum does not match: ${item['file']}',
      );
    }
  }
}

Future<Map<String, Object>> inspectAppDir(Directory appdir) async {
  final libraries = <String, Object>{};
  await for (final file in appdir.list(recursive: true, followLinks: false)) {
    if (file is! File) continue;
    final input = await file.open();
    final magic = await input.read(4);
    await input.close();
    if (magic.length != 4 ||
        magic[0] != 0x7f ||
        String.fromCharCodes(magic.skip(1)) != 'ELF') {
      continue;
    }
    final relative = file.path.substring(appdir.path.length + 1);
    final elf = await runPackagingCommand('readelf', ['-lW', '-dW', file.path]);
    if (elf.contains('/nix/store/') ||
        (relative.endsWith('/libexec/legion-portable-control') &&
            RegExp(r'\((?:RPATH|RUNPATH)\)').hasMatch(elf))) {
      throw StateError('Unsafe library search paths in $relative');
    }
    libraries[relative] = [
      for (final match in RegExp(
        r'Shared library: \[([^\]]+)\]',
      ).allMatches(elf))
        match.group(1)!,
    ];
  }
  return libraries;
}

Future<String> runPackagingCommand(
  String command,
  List<String> arguments,
) async {
  final result = await Process.run(
    command,
    arguments,
    environment: {'LC_ALL': 'C'},
  );
  if (result.exitCode != 0) {
    throw StateError('$command failed: ${result.stderr}');
  }
  return result.stdout as String;
}

Future<String> fileSha256(File file) async => (await runPackagingCommand(
  'sha256sum',
  ['--binary', '--zero', '--', file.path],
)).substring(0, 64);
