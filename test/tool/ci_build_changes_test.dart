import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('tool/ci_build_changes.sh').absolute.path;
  late Directory root;
  late String base;

  String git(List<String> arguments) {
    final result = Process.runSync(
      'git',
      arguments,
      workingDirectory: root.path,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return '${result.stdout}'.trim();
  }

  ProcessResult select({bool withBase = true, String? output}) =>
      Process.runSync(
        'bash',
        [
          script,
          if (withBase) ...['--base', base],
        ],
        workingDirectory: root.path,
        environment: {'GITHUB_OUTPUT': ?output},
      );

  void commit() {
    git(['add', '-A']);
    git(['commit', '--allow-empty', '-m', 'fixture']);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('ci-changes-');
    git(['init']);
    git(['config', 'user.name', 'CI test']);
    git(['config', 'user.email', 'test@example.invalid']);
    commit();
    base = git(['rev-parse', 'HEAD']);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('documentation-only changes skip packaging', () {
    for (final name in ['README.md', 'docs/nix.md', 'AGENTS.md']) {
      File('${root.path}/$name')
        ..createSync(recursive: true)
        ..writeAsStringSync('documentation\n');
    }
    commit();
    expect(select().stdout, 'build=false\n');
  });

  test('build inputs and workflows require packaging', () {
    for (final name in [
      'lib/main.dart',
      'linux/CMakeLists.txt',
      'control/test/fixtures.nix',
      'telemetry/package.nix',
      'packaging/nix/frontend.nix',
      'assets/icon.svg',
      'tool/build_appimage.sh',
      'test/tool/ci_build_changes_test.dart',
      'integration_test/app_test.dart',
      'pubspec.lock',
      'flake.nix',
      'flake.lock',
      '.github/workflows/ci.yml',
      'THIRD_PARTY_NOTICES.md',
    ]) {
      base = git(['rev-parse', 'HEAD']);
      File('${root.path}/$name')
        ..createSync(recursive: true)
        ..writeAsStringSync('input\n');
      commit();
      expect(select().stdout, 'build=true\n', reason: name);
    }
  });

  test('renames and deletions retain build paths', () {
    final source = File('${root.path}/lib/old.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('original\n');
    commit();
    base = git(['rev-parse', 'HEAD']);
    Directory('${root.path}/docs').createSync();
    source.renameSync('${root.path}/docs/old.md');
    commit();
    expect(select().stdout, 'build=true\n');
    final deleted = File('${root.path}/lib/deleted.dart')
      ..writeAsStringSync('remove me\n');
    commit();
    base = git(['rev-parse', 'HEAD']);
    deleted.deleteSync();
    commit();
    expect(select().stdout, 'build=true\n');
  });

  test('main and tag calls run every check and append GitHub output', () {
    final output = File('${root.path}/output')
      ..writeAsStringSync('previous=yes\n');
    final result = select(withBase: false, output: output.path);
    expect(result.exitCode, 0);
    expect(result.stdout, 'build=true\n');
    expect(output.readAsStringSync(), 'previous=yes\nbuild=true\n');
  });

  test('invalid refs fail instead of skipping checks', () {
    base = 'missing-commit';
    expect(select().exitCode, isNot(0));
  });
}
