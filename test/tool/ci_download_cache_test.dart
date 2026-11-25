@Tags(['tooling'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Exercise the action's actual shell step without network access or a cache API.
String actionScript(String action, String step) {
  final source = File('.github/actions/$action/action.yml').readAsStringSync();
  final block = source.split('    - name: $step\n')[1].split('\n    - ').first;
  return block
      .split('      run: |\n')[1]
      .split('\n')
      .where((line) => line.startsWith('        '))
      .map((line) => line.substring(8))
      .join('\n');
}

void main() {
  late Directory root;
  late String digest;

  void write(String path, String content) {
    File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  ProcessResult run(String script, {bool local = false}) => Process.runSync(
    'bash',
    ['-euo', 'pipefail', '-c', script],
    workingDirectory: root.path,
    environment: {
      'PATH': '${root.path}/bin:${Platform.environment['PATH']}',
      'RUNNER_TEMP': '${root.path}/temp',
      'RUNNER_KIND': local ? 'self-hosted' : 'github-hosted',
      'HOME': root.path,
      'GITHUB_ENV': '${root.path}/env',
      'GITHUB_OUTPUT': '${root.path}/output',
      'DIGEST': digest,
      'FIXTURE_ROOT': root.path,
    },
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('ci-download-cache-');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/temp').createSync();
    write(
      'tool/cache_flutter_archive.sh',
      File('tool/cache_flutter_archive.sh').readAsStringSync(),
    );
    write('download', 'verified download bytes\n');
    digest =
        (Process.runSync('sha256sum', ['${root.path}/download']).stdout
                as String)
            .split(' ')
            .first;
    write('checksums', '$digest *jammy-server-cloudimg-amd64.img\n');
    write('bin/curl', r'''#!/usr/bin/env bash
set -euo pipefail
echo download >> "$FIXTURE_ROOT/requests"
source_file="$FIXTURE_ROOT/download"
output=
while (($#)); do
  case "$1" in
    *SHA256SUMS) source_file="$FIXTURE_ROOT/checksums"; shift ;;
    -o|--output) output=$2; shift 2 ;;
    *) shift ;;
  esac
done
cp "$source_file" "$output"
''');
    Process.runSync('chmod', ['+x', '${root.path}/bin/curl']);
    write(
      'packaging/appimage/build-inputs.json',
      jsonEncode({
        'flutter': {
          'sha256': digest,
          'url': 'https://example.invalid/flutter.tar.xz',
        },
      }),
    );
  });

  for (final entry in {
    'package-inputs': ('Verify or download the pinned SDK', 'flutter.tar.xz'),
    'ubuntu-image': ('Verify or download the Ubuntu image', 'jammy.img'),
  }.entries) {
    final (step, name) = entry.value;
    test('${entry.key} uses a verified cache hit without downloading', () {
      File('${root.path}/download').copySync('${root.path}/temp/$name');
      final result = run(actionScript(entry.key, step));
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(File('${root.path}/requests').existsSync(), isFalse);
    });

    test('${entry.key} replaces missing or corrupt cached bytes', () {
      for (final corrupt in [false, true]) {
        final file = File('${root.path}/temp/$name');
        if (corrupt) file.writeAsStringSync('corrupt cache');
        final result = run(actionScript(entry.key, step));
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(file.readAsStringSync(), 'verified download bytes\n');
        file.deleteSync();
      }
      expect(File('${root.path}/requests').readAsLinesSync(), hasLength(2));
    });

    test('${entry.key} rejects a downloaded checksum mismatch', () {
      write('download', 'tampered download');
      final result = run(actionScript(entry.key, step));
      expect(result.exitCode, isNot(0));
    });
  }

  test('local package jobs reuse the archive after job cleanup', () {
    final step = actionScript(
      'package-inputs',
      'Verify or download the pinned SDK',
    );
    expect(run(step, local: true).exitCode, 0);
    Directory('${root.path}/temp').deleteSync(recursive: true);
    expect(run(step, local: true).exitCode, 0);
    expect(File('${root.path}/requests').readAsLinesSync(), hasLength(1));
  });

  test('Ubuntu refreshes its checksum before selecting an image cache key', () {
    final result = run(
      actionScript('ubuntu-image', 'Fetch the current official checksum'),
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(File('${root.path}/output').readAsStringSync(), 'sha256=$digest\n');
    final action = File('.github/actions/ubuntu-image/action.yml')
        .readAsStringSync();
    expect(
      action,
      contains('key: ubuntu-jammy-amd64-\${{ steps.checksum.outputs.sha256 }}'),
    );
  });

  test('Ubuntu rejects ambiguous checksums instead of selecting a cache', () {
    write(
      'checksums',
      '$digest *jammy-server-cloudimg-amd64.img\n$digest *jammy-server-cloudimg-amd64.img\n',
    );
    expect(
      run(actionScript('ubuntu-image', 'Fetch the current official checksum'))
          .exitCode,
      isNot(0),
    );
    expect(File('${root.path}/output').existsSync(), isFalse);
  });
}
