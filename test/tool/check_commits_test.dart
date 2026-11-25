@Tags(['tooling'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_commits.dart';
import '../support/git_fixture.dart';

void main() {
  late Directory root;
  late GitFixture repository;
  late String base;

  String git(List<String> arguments) => repository.git(arguments);

  void commit(String message) => git([
    '-c',
    'commit.gpgsign=false',
    'commit',
    '--allow-empty',
    '-qm',
    message,
  ]);

  setUp(() {
    root = Directory.systemTemp.createTempSync('commit-conventions-');
    addTearDown(() => root.deleteSync(recursive: true));
    repository = GitFixture(root);
    addTearDown(repository.dispose);
    repository.initialize(name: 'Commit test');
    commit('Existing history without a prefix');
    base = git(['rev-parse', 'HEAD']);
  });

  test('checks new branch commits but excludes base history and merges', () {
    commit('fix(fans): preserve the saved curve');
    git(['checkout', '-qb', 'feature']);
    commit('feat(control)!: require the new protocol');
    commit('Forgot the prefix');
    git(['checkout', 'main']);
    commit('docs: explain the protocol migration');
    git([
      '-c',
      'commit.gpgsign=false',
      'merge',
      '--no-ff',
      'feature',
      '-m',
      'Merge feature',
    ]);
    final invalid = invalidCommitSubjects(
      root,
      base,
      git(['rev-parse', 'HEAD']),
    );
    expect(invalid, hasLength(1));
    expect(invalid.single, endsWith(' Forgot the prefix'));
  });

  test('fails on an invalid or unavailable revision', () {
    expect(
      () => invalidCommitSubjects(root, '--all', base),
      throwsFormatException,
    );
    expect(() => invalidCommitSubjects(root, '0' * 40, base), throwsStateError);
  });

  test('the CI command exits unsuccessfully for a rejected commit', () {
    commit('Missing type');
    final script = File('tool/check_commits.dart').absolute.path;
    final result = Process.runSync(
      'dart',
      [
        script,
        base,
        git(['rev-parse', 'HEAD']),
      ],
      workingDirectory: root.path,
      environment: repository.environment,
      includeParentEnvironment: false,
    );
    expect(result.exitCode, 1);
    expect(result.stderr, contains('Missing type'));
  });
}
