import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('tool/record_package_test_results.dart').absolute.path;
  const sourceHash =
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
  const evidenceHash =
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
  late Directory directory;
  late File manifest;

  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'qualification with spaces ',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    manifest = File('${directory.path}/manifest.json');
    File('${directory.path}/native-source.tar.gz').writeAsStringSync('abc');
  });

  Future<ProcessResult> run(List<String> arguments) =>
      Process.run('dart', [script, ...arguments]);

  Future<ProcessResult> record(String format, {String modified = ''}) => run([
    'distro',
    directory.path,
    'fixture-commit',
    modified,
    'fixture-image-checksum',
    'Nehalem',
    format,
  ]);

  for (final format in ['native', 'appimage', 'deb']) {
    for (final modified in ['', ' M tool/example.dart\n?? quoted "file"']) {
      test('$format records hashes and modified=${modified.isNotEmpty}', () async {
        File('${directory.path}/$format-qualification.tar.gz')
            .writeAsStringSync('');
        final result = await record(format, modified: modified);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(jsonDecode(manifest.readAsStringSync()), {
          'commit': 'fixture-commit',
          'source_worktree_modified': modified.isNotEmpty,
          'cloud_image_sha256': 'fixture-image-checksum',
          'cpu_model': 'Nehalem',
          'files': {
            'native-source.tar.gz': sourceHash,
            '$format-qualification.tar.gz': evidenceHash,
          },
          'scope':
              'Portable control with a synthetic CLI in a disposable distro VM',
          'hardware': 'unverified',
          'desktop_authentication': 'unverified',
          'appimage': format == 'appimage'
              ? 'FUSE, extraction, desktop launch, and synthetic helper control verified'
              : 'unverified',
          'deb': format == 'deb'
              ? 'install, desktop, helper, upgrade, and purge verified'
              : 'unverified',
        });
      });
    }
  }

  test('missing evidence leaves an existing manifest intact', () async {
    manifest.writeAsStringSync('previous manifest');
    final result = await record('native');
    expect(result.exitCode, 1);
    expect(manifest.readAsStringSync(), 'previous manifest');
  });

  test('NixOS evidence is added without losing existing fields', () async {
    final existing = {
      'files': {'appimage-qualification.tar.gz': 'existing-hash'},
      'hardware': 'unverified',
      'extra': {'kept': true},
    };
    manifest.writeAsStringSync(jsonEncode(existing));
    File('${directory.path}/appimage-nixos-qualification.tar.gz')
        .writeAsStringSync('');
    final result = await run(['nixos', directory.path]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(jsonDecode(manifest.readAsStringSync()), {
      ...existing,
      'files': {
        'appimage-qualification.tar.gz': 'existing-hash',
        'appimage-nixos-qualification.tar.gz': evidenceHash,
      },
    });
    expect(File('${manifest.path}.tmp').existsSync(), isFalse);
  });

  test('missing NixOS evidence leaves the manifest intact', () async {
    const original =
        '{"files":{"existing.tar.gz":"hash"},"hardware":"unverified"}\n';
    manifest.writeAsStringSync(original);
    final result = await run(['nixos', directory.path]);
    expect(result.exitCode, 1);
    expect(manifest.readAsStringSync(), original);
    expect(File('${manifest.path}.tmp').existsSync(), isFalse);
  });

  test(
    'invalid manifest stops the NixOS update without replacing it',
    () async {
      manifest.writeAsStringSync('invalid JSON');
      final result = await run(['nixos', directory.path]);
      expect(result.exitCode, isNot(0));
      expect(manifest.readAsStringSync(), 'invalid JSON');
    },
  );

  test('unknown formats and incomplete commands fail before writing', () async {
    expect((await record('rpm')).exitCode, 64);
    expect((await run(['nixos'])).exitCode, 64);
    expect((await run([])).exitCode, 64);
    expect(manifest.existsSync(), isFalse);
  });
}
