@Tags(['tooling'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/git_fixture.dart';

void main() {
  final hook = File('.githooks/pre-push').absolute.path;
  late Directory workspace;
  late GitFixture repository;
  late File calls;
  late File workdirs;
  late Map<String, String> environment;

  void commitFile(String path) {
    File('${repository.root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync('fixture\n');
    repository.git(['add', '.']);
    repository.git(['commit', '-qm', 'fix: fixture change']);
  }

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('pre-push-test-');
    addTearDown(() => workspace.deleteSync(recursive: true));
    repository = GitFixture(Directory('${workspace.path}/source'));
    addTearDown(repository.dispose);
    repository.initialize();
    Directory('${repository.root.path}/tool').createSync();
    File('tool/ci_build_changes.sh')
        .copySync('${repository.root.path}/tool/ci_build_changes.sh');
    commitFile('lib/main.dart');
    commitFile('tool/existing.dart');
    repository.git(['update-ref', 'refs/remotes/origin/main', 'HEAD']);
    repository.git(['checkout', '-qb', 'feature']);
    calls = File('${workspace.path}/calls');
    workdirs = File('${workspace.path}/workdirs');
    final bin = Directory('${workspace.path}/bin')..createSync();
    for (final command in ['flutter', 'dart']) {
      final stub = File('${bin.path}/$command')
        ..writeAsStringSync('''#!/usr/bin/env bash
printf '%s\\n' '$command '"\$*" >> '${calls.path}'
printf '%s\\n' "\$PWD" >> '${workdirs.path}'
if [[ '$command' == flutter && "\$1" == test && "\${FAIL_TESTS:-}" == true ]]; then
  exit 9
fi
''');
      expect(Process.runSync('chmod', ['+x', stub.path]).exitCode, 0);
    }
    environment = {
      ...repository.environment,
      'PATH': '${bin.path}:${Platform.environment['PATH']}',
      'GIT_DIR': '${repository.root.path}/.git',
      'GIT_WORK_TREE': repository.root.path,
    };
  });

  Future<List<String>> push(List<String> refs, {int expectedExit = 0}) async {
    final head = repository.git(['rev-parse', 'HEAD']);
    final before = repository.git(['reflog', '--all', '--format=%H %gs']);
    final status = repository.git(['status', '--porcelain']);
    final process = await Process.start(
      'bash',
      [hook],
      workingDirectory: repository.root.path,
      environment: environment,
      includeParentEnvironment: false,
    );
    final output = process.stdout.transform(utf8.decoder).join();
    final error = process.stderr.transform(utf8.decoder).join();
    for (final ref in refs) {
      process.stdin.writeln('$ref $head $ref ${'0' * 40}');
    }
    await process.stdin.close();
    final code = await process.exitCode;
    expect(code, expectedExit, reason: '${await output}\n${await error}');
    expect(repository.git(['reflog', '--all', '--format=%H %gs']), before);
    expect(repository.git(['status', '--porcelain']), status);
    expect(workdirs.readAsLinesSync(), everyElement(repository.root.path));
    return calls
        .readAsLinesSync()
        .where((line) => line.startsWith('flutter test '))
        .toList();
  }

  test('an unrelated Flutter push excludes tooling tests', () async {
    commitFile('lib/features/fans/fans_page.dart');
    final tests = await push(['refs/heads/feature']);
    expect(tests, hasLength(1));
    expect(tests.single, contains('--exclude-tags tooling'));
  });

  test(
    'unstaged tooling changes select every test in the current worktree',
    () async {
      File('${repository.root.path}/tool/existing.dart')
          .writeAsStringSync('local tooling edit\n');
      final tests = await push(['refs/heads/feature']);
      expect(tests.single, isNot(contains('--exclude-tags')));
    },
  );

  test('staged tooling changes select every test', () async {
    File('${repository.root.path}/tool/existing.dart')
        .writeAsStringSync('staged tooling edit\n');
    repository.git(['add', 'tool/existing.dart']);
    final tests = await push(['refs/heads/feature']);
    expect(tests.single, isNot(contains('--exclude-tags')));
  });

  test('untracked tooling changes select every test', () async {
    File('${repository.root.path}/tool/new.dart')
        .writeAsStringSync('untracked tooling edit\n');
    final tests = await push(['refs/heads/feature']);
    expect(tests.single, isNot(contains('--exclude-tags')));
  });

  test('staged app-only changes still exclude tooling tests', () async {
    File('${repository.root.path}/lib/main.dart')
        .writeAsStringSync('staged app edit\n');
    repository.git(['add', 'lib/main.dart']);
    final tests = await push(['refs/heads/feature']);
    expect(tests.single, contains('--exclude-tags tooling'));
  });

  test(
    'tooling changes earlier in the branch still select every test',
    () async {
      commitFile('tool/check_commits.dart');
      commitFile('lib/features/fans/fans_page.dart');
      final tests = await push(['refs/heads/feature']);
      expect(tests, hasLength(1));
      expect(tests.single, isNot(contains('--exclude-tags')));
    },
  );

  test('missing main falls back to every test', () async {
    repository.git(['update-ref', '-d', 'refs/remotes/origin/main']);
    commitFile('lib/features/fans/fans_page.dart');
    final tests = await push(['refs/heads/feature']);
    expect(tests.single, isNot(contains('--exclude-tags')));
  });

  test('an older selector without tooling output runs every test', () async {
    File('${repository.root.path}/tool/ci_build_changes.sh')
        .writeAsStringSync('#!/usr/bin/env bash\necho integration=false\n');
    commitFile('lib/features/fans/fans_page.dart');
    final tests = await push(['refs/heads/feature']);
    expect(tests.single, isNot(contains('--exclude-tags')));
  });

  test('a failing app test still blocks the push', () async {
    commitFile('lib/features/fans/fans_page.dart');
    environment['FAIL_TESTS'] = 'true';
    final tests = await push(['refs/heads/feature'], expectedExit: 9);
    expect(tests.single, contains('--exclude-tags tooling'));
  });

  test(
    'a release tag selects every test once for the current worktree',
    () async {
      commitFile('lib/features/fans/fans_page.dart');
      repository.git(['tag', 'v1.0.0']);
      final tests = await push(['refs/heads/feature', 'refs/tags/v1.0.0']);
      expect(tests, hasLength(1));
      expect(tests.single, isNot(contains('--exclude-tags')));
    },
  );
}
