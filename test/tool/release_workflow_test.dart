// Exercise release validation and GitHub writes with local files and fake replies.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/packaging_files.dart';
import '../../tool/packaging_versions.dart';
import '../../tool/release_workflow.dart' as release;

void archiveContents(File path, Map<String, String> files) {
  final staging = Directory.systemTemp.createTempSync('release-fixture-');
  try {
    for (final entry in files.entries) {
      File('${staging.path}/${entry.key}')
        ..createSync(recursive: true)
        ..writeAsStringSync(entry.value);
    }
    packagingCommand('tar', [
      '-czf',
      path.path,
      '-C',
      staging.path,
      '--',
      ...files.keys,
    ]);
  } finally {
    staging.deleteSync(recursive: true);
  }
}

void archiveJson(
  File path,
  String name,
  Object value, {
  Map<String, Object> additional = const {},
}) => archiveContents(path, {
  name: jsonEncode(value),
  for (final entry in additional.entries) entry.key: jsonEncode(entry.value),
});

Matcher failsWith(String message) => throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'message',
    contains(message),
  ),
);

class ReleaseFixture {
  ReleaseFixture({this.version = '1.2.3+7'}) {
    root.createSync();
    git(['init', '-q', '--initial-branch=main']);
    git(['config', 'user.name', 'Release test']);
    git(['config', 'user.email', 'release@example.invalid']);
    File('${root.path}/pubspec.yaml')
        .writeAsStringSync('name: fixture\nversion: $version\n');
    git(['add', '.']);
    git(['commit', '-qm', 'fixture']);
    commit = git(['rev-parse', 'HEAD']);
    git(['tag', '-a', tag, '-m', 'fixture release']);
    binary.createSync(recursive: true);
    qa.createSync();
    final helper = File('${payload.path}/${release.releaseHelperPath}')
      ..createSync(recursive: true)
      ..writeAsBytesSync([
        0x7f,
        ...utf8.encode('ELFsynthetic native helper'),
        0,
        0xff,
      ]);
    packagingCommand('chmod', ['755', helper.path]);
    packageAppImageFixture();
    final bundle = {
      '.': {'type': 'directory', 'mode': '755'},
      './legion_frontend': {'type': 'file', 'mode': '755', 'sha256': 'b' * 64},
      './lib/libapp.so': {'type': 'file', 'mode': '644', 'sha256': 'c' * 64},
      './libexec/legion-portable-control': {
        'type': 'file',
        'mode': '755',
        'sha256': hash(helper),
      },
    };
    sources = {
      'format': 4,
      'inputs': {'commit': commit},
      'build_config': {'portable_control': true},
      'bundle': bundle,
    };
    archiveJson(
      File('${binary.path}/$source'),
      './SOURCE-MANIFEST.json',
      sources,
    );
    manifest = {
      'format': 1,
      'version': version,
      'source_commit': commit,
      'architecture': 'x86_64',
      'portable_control': true,
      'default_control_mode': 'privilegedControlHelper',
      'runtime_size': runtimeSize,
      'appdir': {
        for (final entry in bundle.entries)
          './usr/lib/legion_frontend${entry.key.substring(1)}': entry.value,
      },
    };
    refresh();
    refreshDebian();
  }

  final temporary = Directory.systemTemp.createTempSync('release with spaces ');
  late final root = Directory('${temporary.path}/source');
  late final inputs = Directory('${temporary.path}/inputs');
  late final binary = Directory('${inputs.path}/appimage-release');
  late final qa = Directory('${inputs.path}/appimage-qualification');
  late final output = Directory('${temporary.path}/prepared');
  late final deb = Directory('${inputs.path}/deb-release');
  late final payload = Directory('${temporary.path}/payload');
  late int runtimeSize;
  late final String commit;
  final String version;
  late final tag = 'v${version.split('+').first}';
  late final prefix = 'legion-frontend-$version-x86_64';
  late final image = '$prefix.AppImage';
  late final source = '$prefix-source.tar.gz';
  late final metadata = '$prefix.json';
  late Map sources, manifest, evidence, debManifest;

  String git(List<String> arguments) => release.releaseGit(root, arguments);
  String hash(File path) => release.releaseSha256(path);
  Map<String, Object> prepare() =>
      release.prepareRelease(root, tag, inputs, output);

  void checksums(Directory directory, List<String> names) {
    File('${directory.path}/SHA256SUMS').writeAsStringSync(
      names
          .map((name) => '${hash(File('${directory.path}/$name'))}  $name\n')
          .join(),
    );
  }

  void refresh() {
    manifest['files'] = {
      for (final name in [image, source])
        name: hash(File('${binary.path}/$name')),
    };
    writePackagingJson(File('${binary.path}/$metadata'), manifest);
    checksums(binary, [image, source, metadata]);
    archiveJson(
      File('${qa.path}/appimage-qualification.tar.gz'),
      'appimage-release-manifest.json',
      manifest,
    );
    File('${qa.path}/native-source.tar.gz')
        .writeAsStringSync('native source fixture');
    File('${qa.path}/qualification.log')
        .writeAsStringSync('PASS: synthetic helper and desktop launch\n');
    evidence = {
      'commit': commit,
      'source_worktree_modified': false,
      'appimage': release.qualifiedAppImage,
      'files': {
        for (final name in [
          'native-source.tar.gz',
          'appimage-qualification.tar.gz',
        ])
          name: hash(File('${qa.path}/$name')),
      },
    };
    writePackagingJson(File('${qa.path}/manifest.json'), evidence);
  }

  void packageAppImageFixture() {
    final squashfs = File('${temporary.path}/payload.squashfs');
    if (squashfs.existsSync()) squashfs.deleteSync();
    packagingCommand('mksquashfs', [
      payload.path,
      squashfs.path,
      '-noappend',
      '-processors',
      '1',
      '-no-progress',
    ]);
    final runtime = utf8.encode('AppImage runtime fixture');
    runtimeSize = runtime.length;
    File('${binary.path}/$image')
        .writeAsBytesSync([...runtime, ...squashfs.readAsBytesSync()]);
  }

  void refreshDebian({Map<String, Object> changes = const {}}) {
    deb.createSync(recursive: true);
    final names = release.debianNames({'version': version});
    File('${payload.path}/DEBIAN/control')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'Package: fixture\nVersion: ${debianVersion(version)}\nArchitecture: amd64\n'
        'Maintainer: Test <test@example.invalid>\nDescription: Package fixture\n',
      );
    packagingCommand('dpkg-deb', [
      '--root-owner-group',
      '--build',
      payload.path,
      '${deb.path}/${names[0]}',
    ]);
    archiveJson(
      File('${deb.path}/${names[1]}'),
      './SOURCE-MANIFEST.json',
      sources,
    );
    debManifest = {
      'format': 1,
      'version': version,
      'package_version': debianVersion(version),
      'architecture': 'amd64',
      'source_commit': commit,
      'portable_control': true,
      'default_control_mode': 'privilegedControlHelper',
      'bundle': sources['bundle'],
      'files': {
        for (final name in names.take(2)) name: hash(File('${deb.path}/$name')),
      },
      ...changes,
    };
    writePackagingJson(File('${deb.path}/${names[2]}'), debManifest);
    checksums(deb, names.take(3).toList());
    for (final os in {
      'ubuntu': 'ID=ubuntu\nVERSION_ID="22.04"\n',
      'debian': 'ID=debian\nVERSION_ID="12"\n',
    }.entries) {
      final directory = Directory('${inputs.path}/deb-${os.key}-qualification')
        ..createSync(recursive: true);
      archiveContents(File('${directory.path}/deb-qualification.tar.gz'), {
        'deb-release-manifest.json': jsonEncode(debManifest),
        'deb-os-release': os.value,
        'deb-checks.json': jsonEncode({
          for (final name in release.debianChecks) name: true,
        }),
      });
      File('${directory.path}/native-source.tar.gz')
          .writeAsStringSync('Debian VM source fixture');
      File('${directory.path}/qualification.log')
          .writeAsStringSync('PASS: package VM checks\n');
      writePackagingJson(File('${directory.path}/manifest.json'), {
        'commit': commit,
        'source_worktree_modified': false,
        'deb': release.qualifiedDeb,
        'files': {
          for (final name in [
            'native-source.tar.gz',
            'deb-qualification.tar.gz',
          ])
            name: hash(File('${directory.path}/$name')),
        },
      });
    }
  }

  void enableNativeRuntime() {
    const library = 'usr/lib/legion_frontend/lib/libgtk-3.so.0';
    final entry = {'type': 'file', 'mode': '644', 'sha256': 'd' * 64};
    manifest['appdir']['./$library'] = entry;
    sources['bundle']['./lib/libgtk-3.so.0'] = entry;
    sources['build_config']['static_portable_helper'] = true;
    final native = {
      'format': 1,
      'files': {
        library: {'sha256': 'd' * 64, 'package': 'gtk'},
      },
      'packages': {
        'gtk': {'source': 'gtk', 'source_version': '1'},
      },
      'sources': {
        'gtk': {
          'version': '1',
          'archives': {'gtk.tar.xz': 'e' * 64},
        },
      },
      'helper': {
        'linkage': 'static',
        'cleanup': {'size': 4096, 'sha256': 'f' * 64},
      },
    };
    sources['release_inputs'] = {
      './native/sources/gtk/gtk.tar.xz': {'sha256': 'e' * 64},
      './native/portable-cleanup.elf': {'sha256': 'f' * 64},
    };
    manifest['native_runtime'] = native;
    archiveJson(
      File('${binary.path}/$source'),
      './SOURCE-MANIFEST.json',
      sources,
      additional: {'./release-inputs/native/native-runtime.json': native},
    );
    refresh();
    refreshDebian();
  }

  void addNixosEvidence({
    String? imageSha256,
    String? status,
    bool shutdown = true,
  }) {
    const name = 'appimage-nixos-qualification.tar.gz';
    archiveJson(File('${qa.path}/$name'), 'manifest.json', {
      'commit': commit,
      'appimage_sha256': imageSha256 ?? hash(File('${binary.path}/$image')),
      'nixos':
          status ??
          'official appimage-run desktop and privileged control verified',
      if (shutdown)
        'desktop_shutdown':
            'X11 close button and Wayland window close verified',
    });
    evidence['files'][name] = hash(File('${qa.path}/$name'));
    writePackagingJson(File('${qa.path}/manifest.json'), evidence);
  }

  void replaceDebianEvidence(String member, String value) {
    final directory = Directory('${inputs.path}/deb-debian-qualification');
    final archive = File('${directory.path}/deb-qualification.tar.gz');
    final names = packagingCommand('tar', [
      '-tzf',
      archive.path,
    ]).trim().split('\n');
    final files = {
      for (final name in names) name: release.archivedText(archive, name),
    };
    files[member] = value;
    archiveContents(archive, files);
    final qa = release.readReleaseJson(File('${directory.path}/manifest.json'));
    qa['files'][fileName(archive)] = hash(archive);
    writePackagingJson(File('${directory.path}/manifest.json'), qa);
  }

  Future<Object?> api(String path, {Map? existing, String? target}) async {
    if (path.contains('/git/ref/tags/')) {
      return {
        'object': {'type': 'tag', 'sha': 'annotated-object'},
      };
    }
    if (path.contains('/git/tags/')) {
      return {
        'object': {'type': 'commit', 'sha': target ?? commit},
      };
    }
    return existing == null ? [] : [existing];
  }

  Map uploadedRelease() {
    final plan = release.readReleaseJson(
      File('${output.path}/release-plan.json'),
    );
    return {
      'tag_name': tag,
      'draft': true,
      'prerelease': plan['prerelease'],
      'assets': [
        for (final entry in (plan['assets'] as Map).entries)
          {
            'name': entry.key,
            'state': 'uploaded',
            'digest': 'sha256:${entry.value}',
            'size': File('${output.path}/${entry.key}').lengthSync(),
          },
      ],
    };
  }
}

void main() {
  late ReleaseFixture fixture;
  setUp(() {
    fixture = ReleaseFixture();
    addTearDown(() => fixture.temporary.deleteSync(recursive: true));
  });

  test('native runtime requires normal window close evidence', () {
    fixture.enableNativeRuntime();
    fixture.addNixosEvidence(shutdown: false);
    expect(fixture.prepare, failsWith('NixOS acceptance'));
  });

  test('bundled native runtime requires NixOS acceptance', () {
    fixture.enableNativeRuntime();
    expect(fixture.prepare, failsWith('evidence file list'));
  });

  test('static build cannot omit native runtime metadata', () {
    fixture.enableNativeRuntime();
    fixture.manifest.remove('native_runtime');
    fixture.refresh();
    expect(fixture.prepare, failsWith('lacks its native runtime'));
  });

  test('native sources and both host checks are retained', () {
    fixture.enableNativeRuntime();
    fixture.addNixosEvidence();
    final plan = fixture.prepare();
    final evidence = (plan['assets'] as Map).keys.cast<String>().firstWhere(
      (name) => name.endsWith('acceptance.tar.gz'),
    );
    expect(
      packagingCommand('tar', ['-tzf', '${fixture.output.path}/$evidence']),
      contains('appimage-nixos-qualification.tar.gz'),
    );
  });

  test('NixOS acceptance cannot qualify another AppImage', () {
    fixture.enableNativeRuntime();
    fixture.addNixosEvidence(imageSha256: 'f' * 64);
    expect(fixture.prepare, failsWith('NixOS acceptance'));
  });

  test('custom launcher evidence cannot qualify the official runner', () {
    fixture.enableNativeRuntime();
    fixture.addNixosEvidence(
      status: 'host-namespace desktop and static helper control verified',
    );
    expect(fixture.prepare, failsWith('NixOS acceptance'));
  });

  test('direct launch evidence cannot qualify the official runner', () {
    fixture.enableNativeRuntime();
    fixture.addNixosEvidence(
      status:
          'direct FUSE launch with nix-ld and static helper control verified',
    );
    expect(fixture.prepare, failsWith('NixOS acceptance'));
  });

  test('obsolete control evidence cannot qualify the official runner', () {
    fixture.enableNativeRuntime();
    fixture.addNixosEvidence(
      status: 'official appimage-run desktop and temporary control verified',
    );
    expect(fixture.prepare, failsWith('NixOS acceptance'));
  });

  test('runtime library must match the shipped file', () {
    fixture.enableNativeRuntime();
    fixture.manifest['native_runtime']['files']['usr/lib/legion_frontend/lib/libgtk-3.so.0']['sha256'] =
        '0' * 64;
    expect(
      () => release.validateAppImageRuntime(
        fixture.manifest,
        fixture.sources,
        fixture.manifest['native_runtime'],
      ),
      failsWith('shipped file'),
    );
  });

  test('native library source archive cannot be omitted', () {
    fixture.enableNativeRuntime();
    fixture.sources['release_inputs'].remove('./native/sources/gtk/gtk.tar.xz');
    expect(
      () => release.validateAppImageRuntime(
        fixture.manifest,
        fixture.sources,
        fixture.manifest['native_runtime'],
      ),
      failsWith('exact native archive'),
    );
  });

  test(
    'native attribution, helper configuration, and cleanup remain mandatory',
    () {
      fixture.enableNativeRuntime();
      final originalManifest = jsonEncode(fixture.manifest);
      final originalSources = jsonEncode(fixture.sources);
      final mutations = <(String, void Function(Map, Map))>[
        (
          'source package attribution',
          (manifest, sources) {
            manifest['native_runtime']['packages'].clear();
          },
        ),
        (
          'exact source version',
          (manifest, sources) {
            manifest['native_runtime']['sources']['gtk']['version'] = '2';
          },
        ),
        (
          'bundled GTK',
          (manifest, sources) {
            manifest['native_runtime']['files'].clear();
          },
        ),
        (
          'static helper build configuration',
          (manifest, sources) {
            sources['build_config'].remove('static_portable_helper');
          },
        ),
        (
          'bounded cleanup ELF',
          (manifest, sources) {
            manifest['native_runtime']['helper']['cleanup']['size'] = 64 * 1024;
          },
        ),
        (
          'bounded cleanup ELF',
          (manifest, sources) {
            manifest['native_runtime']['helper']['cleanup']['size'] = 0;
          },
        ),
        (
          'bounded cleanup ELF',
          (manifest, sources) {
            sources['release_inputs'].remove('./native/portable-cleanup.elf');
          },
        ),
      ];
      for (final (message, mutate) in mutations) {
        final manifest = jsonDecode(originalManifest) as Map;
        final sources = jsonDecode(originalSources) as Map;
        mutate(manifest, sources);
        expect(
          () => release.validateAppImageRuntime(
            manifest,
            sources,
            manifest['native_runtime'],
          ),
          failsWith(message),
        );
      }
    },
  );

  test('base tag matches pubspec build number and annotated commit', () {
    final metadata = release.checkTag(fixture.root, fixture.tag);
    expect(metadata['version'], '1.2.3+7');
    expect(metadata['commit'], fixture.commit);
    expect(metadata['prerelease'], false);
  });

  test('mismatched or shell-like tag is rejected', () {
    for (final tag in ['v1.2.4', 'v1.2.3+7', 'v1.2.3; touch owned']) {
      expect(() => release.checkTag(fixture.root, tag), throwsStateError);
    }
    expect(File('${fixture.root.path}/owned').existsSync(), false);
  });

  test('prerelease version sets the release flag and download filename', () {
    File('${fixture.root.path}/pubspec.yaml')
        .writeAsStringSync('version: 1.2.3-rc.1+7\n');
    fixture.git(['commit', '-qam', 'prerelease']);
    fixture.git(['tag', 'v1.2.3-rc.1']);
    expect(release.checkTag(fixture.root, 'v1.2.3-rc.1')['prerelease'], true);
    expect(
      release.debianNames({'version': '1.2.3-rc.1+7'}).first,
      'legion-linux-frontend_1.2.3-rc.1+7-1_amd64.deb',
    );
  });

  test(
    'alpha assets verify with safe names and Debian prerelease metadata',
    () {
      final alpha = ReleaseFixture(version: '0.1.0-alpha.2+1');
      addTearDown(() => alpha.temporary.deleteSync(recursive: true));
      final plan = alpha.prepare();
      expect(plan['prerelease'], isTrue);
      const package = 'legion-linux-frontend_0.1.0-alpha.2+1-1_amd64.deb';
      expect((plan['assets'] as Map).keys, contains(package));
      expect(
        packagingCommand('dpkg-deb', [
          '-f',
          '${alpha.output.path}/$package',
          'Version',
        ]).trim(),
        '0.1.0~alpha.2+1-1',
      );
      expect(
        packagingCommand('sha256sum', [
          '--check',
          'SHA256SUMS',
        ], workingDirectory: alpha.output.path),
        contains('$package: OK'),
      );
      packagingCommand('dpkg', [
        '--compare-versions',
        '0.1.0~alpha.2+1-1',
        'lt',
        '0.1.0+1-1',
      ]);
    },
  );

  test('download filename cannot replace the internal Debian version', () {
    final alpha = ReleaseFixture(version: '0.1.0-alpha.2+1');
    addTearDown(() => alpha.temporary.deleteSync(recursive: true));
    alpha.refreshDebian(changes: {'package_version': '0.1.0-alpha.2+1-1'});
    expect(alpha.prepare, failsWith('Debian build differs'));
  });

  test('check-tag appends the validated GitHub outputs', () async {
    final output = File('${fixture.temporary.path}/github-output')
      ..writeAsStringSync('existing=value\n');
    await release.releaseMain(
      ['check-tag', fixture.tag],
      fixture.root,
      {'GITHUB_OUTPUT': output.path},
    );
    expect(
      output.readAsStringSync(),
      'existing=value\ntag=${fixture.tag}\ncommit=${fixture.commit}\n',
    );
  });

  test('advanced main cannot be released as the old tag', () {
    File('${fixture.root.path}/README.md').writeAsStringSync('newer main');
    fixture.git(['add', '.']);
    fixture.git(['commit', '-qm', 'newer main']);
    expect(
      () => release.checkTag(fixture.root, fixture.tag),
      failsWith('checked-out commit'),
    );
  });

  test('detached tag clone builds tagged source when main is newer', () {
    File('${fixture.root.path}/README.md').writeAsStringSync('newer main');
    fixture.git(['add', '.']);
    fixture.git(['commit', '-qm', 'newer main']);
    fixture.git(['checkout', '--detach', fixture.tag]);
    final copied = Directory('${fixture.temporary.path}/container source');
    packagingCommand('git', [
      'clone',
      '-q',
      '--depth',
      '1',
      '--no-local',
      '--single-branch',
      fixture.root.uri.toString(),
      copied.path,
    ]);
    expect(release.checkTag(copied, fixture.tag)['commit'], fixture.commit);
  });

  test('prepares complete assets, checksums, and qualification notes', () {
    final plan = fixture.prepare();
    expect((plan['assets'] as Map).length, 9);
    final checksums = release.releaseChecksums(
      fixture.output,
      (plan['assets'] as Map).keys.cast<String>().toSet()..remove('SHA256SUMS'),
    );
    expect(
      checksums[fixture.image],
      fixture.hash(File('${fixture.binary.path}/${fixture.image}')),
    );
    final notes = File('${fixture.output.path}/RELEASE-NOTES.md')
        .readAsStringSync();
    expect(notes, contains('synthetic CLI'));
    expect(notes, contains('password prompts still need qualification'));
    expect(notes, contains(fixture.commit));
    expect(notes, contains('bundled privileged control helper'));
    expect(notes, isNot(contains('Choose')));
    expect(
      packagingCommand('tar', [
        '-tzf',
        '${fixture.output.path}/${fixture.prefix}-acceptance.tar.gz',
      ]),
      contains('appimage-qualification.tar.gz'),
    );
  });

  test('missing Debian acceptance stops the draft', () {
    File('${fixture.inputs.path}/deb-debian-qualification/manifest.json')
        .deleteSync();
    expect(fixture.prepare, throwsStateError);
  });

  for (final obsolete in ['installedService', 'temporaryHelper']) {
    test('rejects obsolete AppImage default $obsolete', () {
      fixture.manifest['default_control_mode'] = obsolete;
      fixture.refresh();
      expect(fixture.prepare, failsWith('AppImage manifest'));
    });

    test('rejects obsolete Debian default $obsolete', () {
      fixture.refreshDebian(changes: {'default_control_mode': obsolete});
      expect(fixture.prepare, failsWith('Debian build differs'));
    });
  }

  test('Debian helper payload must match its source inventory', () {
    File('${fixture.payload.path}/${release.releaseHelperPath}')
        .writeAsStringSync('replacement helper');
    fixture.refreshDebian();
    expect(fixture.prepare, failsWith('Debian helper payload differs'));
  });

  test('Debian helper must be executable', () {
    packagingCommand('chmod', [
      '644',
      '${fixture.payload.path}/${release.releaseHelperPath}',
    ]);
    fixture.refreshDebian();
    expect(fixture.prepare, failsWith('Debian helper payload differs'));
  });

  test('Debian helper cannot be absent', () {
    final helper = File('${fixture.payload.path}/${release.releaseHelperPath}');
    helper.deleteSync();
    fixture.refreshDebian();
    expect(fixture.prepare, failsWith('regular privileged control helper'));
  });

  test('Debian helper cannot be a symbolic link', () {
    final helper = File('${fixture.payload.path}/${release.releaseHelperPath}');
    helper.deleteSync();
    Link(helper.path).createSync('missing');
    fixture.refreshDebian();
    expect(
      fixture.prepare,
      failsWith('regular executable privileged control helper'),
    );
  });

  test('AppImage helper payload must match its source inventory', () {
    fixture.sources['bundle']['./libexec/legion-portable-control']['sha256'] =
        '0' * 64;
    archiveJson(
      File('${fixture.binary.path}/${fixture.source}'),
      './SOURCE-MANIFEST.json',
      fixture.sources,
    );
    fixture.refresh();
    expect(fixture.prepare, failsWith('AppImage helper payload differs'));
  });

  test('AppImage helper must be executable', () {
    packagingCommand('chmod', [
      '644',
      '${fixture.payload.path}/${release.releaseHelperPath}',
    ]);
    fixture.packageAppImageFixture();
    fixture.refresh();
    expect(fixture.prepare, failsWith('AppImage helper payload differs'));
  });

  test('AppImage helper cannot be absent or a symbolic link', () {
    final helper = File('${fixture.payload.path}/${release.releaseHelperPath}');
    helper.deleteSync();
    fixture.packageAppImageFixture();
    fixture.refresh();
    expect(
      fixture.prepare,
      throwsA(anyOf(isA<StateError>(), isA<ProcessException>())),
    );
    Link(helper.path).createSync('missing');
    fixture.packageAppImageFixture();
    fixture.refresh();
    expect(fixture.prepare, failsWith('symlink'));
  });

  test('invalid AppImage payload offsets are rejected', () {
    for (final offset in [null, true, -1, 0, 1.5, '12', 1 << 30]) {
      fixture.manifest['runtime_size'] = offset;
      fixture.refresh();
      expect(fixture.prepare, failsWith('runtime size'));
    }
  });

  test('source companion must require the helper', () {
    fixture.sources['build_config']['portable_control'] = false;
    archiveJson(
      File('${fixture.binary.path}/${fixture.source}'),
      './SOURCE-MANIFEST.json',
      fixture.sources,
    );
    fixture.refresh();
    expect(fixture.prepare, failsWith('describe this portable build'));
  });

  test('modified Debian package is rejected', () {
    final package = release.debianNames({'version': '1.2.3+7'}).first;
    File('${fixture.deb.path}/$package').writeAsStringSync('changed');
    expect(fixture.prepare, failsWith('checksum differs'));
  });

  test('Debian acceptance must match the package', () {
    fixture.refreshDebian();
    fixture.replaceDebianEvidence('deb-release-manifest.json', '{}');
    expect(fixture.prepare, failsWith('different Debian package'));
  });

  test('Debian acceptance requires the declared distribution', () {
    fixture.replaceDebianEvidence(
      'deb-os-release',
      'ID=ubuntu\nVERSION_ID="22.04"\n',
    );
    expect(fixture.prepare, failsWith('wrong distribution'));
  });

  test('failed Debian purge check stops the draft', () {
    fixture.replaceDebianEvidence(
      'deb-checks.json',
      jsonEncode({
        for (final name in release.debianChecks) name: name != 'purge',
      }),
    );
    expect(fixture.prepare, failsWith('has not passed'));
  });

  test('corrupted image is rejected before creating output', () {
    File('${fixture.binary.path}/${fixture.image}')
        .writeAsStringSync('changed');
    expect(fixture.prepare, failsWith('checksum differs'));
    expect(fixture.output.existsSync(), false);
  });

  test('source companion must include the complete helper inventory', () {
    fixture.sources['bundle'].remove('./libexec/legion-portable-control');
    archiveJson(
      File('${fixture.binary.path}/${fixture.source}'),
      './SOURCE-MANIFEST.json',
      fixture.sources,
    );
    fixture.refresh();
    expect(fixture.prepare, failsWith('complete shipped bundle'));
  });

  test('dirty or unqualified VM evidence is rejected', () {
    for (final changes in [
      {'source_worktree_modified': true},
      {'appimage': 'unverified'},
      {'commit': '0' * 40},
    ]) {
      writePackagingJson(File('${fixture.qa.path}/manifest.json'), {
        ...fixture.evidence,
        ...changes,
      });
      expect(fixture.prepare, throwsStateError);
    }
  });

  test('qualification must identify the same release', () {
    archiveJson(
      File('${fixture.qa.path}/appimage-qualification.tar.gz'),
      'appimage-release-manifest.json',
      {...fixture.manifest, 'source_commit': '0' * 40},
    );
    fixture.evidence['files']['appimage-qualification.tar.gz'] = fixture.hash(
      File('${fixture.qa.path}/appimage-qualification.tar.gz'),
    );
    writePackagingJson(
      File('${fixture.qa.path}/manifest.json'),
      fixture.evidence,
    );
    expect(fixture.prepare, failsWith('different release artifacts'));
  });

  test('asset symlink is rejected', () {
    final image = File('${fixture.binary.path}/${fixture.image}')..deleteSync();
    Link(image.path).createSync('${fixture.root.path}/pubspec.yaml');
    expect(fixture.prepare, failsWith('symlink'));
  });

  test('creates only a draft with an existing tag and all assets', () async {
    fixture.prepare();
    final writes = <List<String>>[];
    await release.publishRelease(
      fixture.root,
      fixture.tag,
      fixture.output,
      'owner/repository',
      api: (path) => fixture.api(
        path,
        existing: writes.length == 2 ? fixture.uploadedRelease() : null,
      ),
      command: (arguments) async {
        writes.add(arguments);
      },
    );
    final create = writes[0], upload = writes[1];
    expect(
      create,
      containsAll(['--draft', '--verify-tag', fixture.commit, '--repo']),
    );
    expect(upload.take(2), ['release', 'upload']);
    expect(
      upload.where((argument) => argument.startsWith(fixture.output.path)),
      hasLength(9),
    );
  });

  test('rerun refreshes an existing draft', () async {
    fixture.prepare();
    final writes = <List<String>>[];
    await release.publishRelease(
      fixture.root,
      fixture.tag,
      fixture.output,
      'owner/repository',
      api: (path) => fixture.api(
        path,
        existing: writes.length == 2
            ? fixture.uploadedRelease()
            : {'tag_name': fixture.tag, 'draft': true},
      ),
      command: (arguments) async {
        writes.add(arguments);
      },
    );
    expect(writes.first.take(2), ['release', 'edit']);
    expect(writes[1], contains('--clobber'));
  });

  for (final (description, alter) in <(String, void Function(Map))>[
    (
      'renamed asset',
      (result) => result['assets'][0]['name'] = 'renamed.AppImage',
    ),
    ('missing asset', (result) => (result['assets'] as List).removeLast()),
    (
      'wrong digest',
      (result) => result['assets'][0]['digest'] = 'sha256:${'0' * 64}',
    ),
    ('wrong size', (result) => result['assets'][0]['size'] = 0),
    ('unfinished asset', (result) => result['assets'][0]['state'] = 'starter'),
    ('published release', (result) => result['draft'] = false),
    ('wrong prerelease flag', (result) => result['prerelease'] = true),
  ]) {
    test('successful upload command cannot hide $description', () async {
      fixture.prepare();
      final uploaded = fixture.uploadedRelease();
      alter(uploaded);
      var writes = 0;
      await expectLater(
        release.publishRelease(
          fixture.root,
          fixture.tag,
          fixture.output,
          'owner/repository',
          api: (path) =>
              fixture.api(path, existing: writes == 2 ? uploaded : null),
          command: (_) async {
            writes++;
          },
        ),
        throwsStateError,
      );
      expect(writes, 2);
    });
  }

  test('finds a draft beyond the first release page', () async {
    final draft = {'tag_name': fixture.tag, 'draft': true};
    final paths = <String>[];
    final found = await release.findRelease('owner/repository', fixture.tag, (
      path,
    ) async {
      paths.add(path);
      return paths.length == 1
          ? [
              for (var index = 0; index < 100; index++)
                {'tag_name': 'v0.0.$index', 'draft': false},
            ]
          : [draft];
    });
    expect(found, draft);
    expect(paths, hasLength(2));
    expect(paths.last, endsWith('page=2'));
  });

  test('published release and moved remote tag block writes', () async {
    fixture.prepare();
    for (final scenario in [
      ({'tag_name': fixture.tag, 'draft': false}, fixture.commit),
      (null, '0' * 40),
    ]) {
      final writes = <List<String>>[];
      await expectLater(
        release.publishRelease(
          fixture.root,
          fixture.tag,
          fixture.output,
          'owner/repository',
          api: (path) =>
              fixture.api(path, existing: scenario.$1, target: scenario.$2),
          command: (arguments) async {
            writes.add(arguments);
          },
        ),
        throwsStateError,
      );
      expect(writes, isEmpty);
    }
  });

  test('changed prepared asset blocks all network calls', () async {
    fixture.prepare();
    File('${fixture.output.path}/${fixture.image}')
        .writeAsStringSync('changed');
    final lookups = <String>[];
    await expectLater(
      release.publishRelease(
        fixture.root,
        fixture.tag,
        fixture.output,
        'owner/repository',
        api: (path) async {
          lookups.add(path);
          return null;
        },
        command: (_) async {
          fail('No GitHub writes are allowed');
        },
      ),
      failsWith('asset changed'),
    );
    expect(lookups, isEmpty);
  });

  test('API status handling distinguishes missing and failed requests', () {
    expect(
      release.parseGitHubResponse(
        ProcessResult(
          0,
          0,
          'HTTP/2.0 200 OK\r\nHeader: value\r\n\r\n{"ok":true}',
          '',
        ),
      ),
      {'ok': true},
    );
    expect(
      release.parseGitHubResponse(
        ProcessResult(0, 1, 'HTTP/2.0 404 Not Found\nHeader: value\n\n{}', ''),
      ),
      null,
    );
    expect(
      () => release.parseGitHubResponse(
        ProcessResult(0, 1, 'HTTP/2.0 403 Forbidden\n\n{}', 'forbidden'),
      ),
      failsWith('GitHub lookup failed'),
    );
  });

  test(
    'checksum list rejects duplicates, omissions, and unexpected filenames',
    () {
      final file = File('${fixture.binary.path}/SHA256SUMS');
      final original = file.readAsStringSync();
      for (final contents in [
        '$original${original.split('\n').first}\n',
        '${original.split('\n').first}\n',
        '${'0' * 64}  unexpected\n',
      ]) {
        file.writeAsStringSync(contents);
        expect(
          () => release.releaseChecksums(fixture.binary, {
            fixture.image,
            fixture.source,
            fixture.metadata,
          }),
          throwsStateError,
        );
      }
    },
  );

  test('archived manifest cannot be a symbolic link', () {
    final staging = Directory('${fixture.temporary.path}/linked')..createSync();
    File('${staging.path}/real.json').writeAsStringSync('{}');
    Link('${staging.path}/manifest.json').createSync('real.json');
    final archive = File('${fixture.temporary.path}/linked.tar.gz');
    packagingCommand('tar', [
      '-czf',
      archive.path,
      '-C',
      staging.path,
      'manifest.json',
    ]);
    expect(
      () => release.archivedJson(archive, 'manifest.json'),
      failsWith('regular archived manifest'),
    );
  });
}
