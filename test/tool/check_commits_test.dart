import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_commits.dart';

void main() {
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
    git(['init', '-b', 'main']);
    git(['config', 'user.name', 'Commit test']);
    git(['config', 'user.email', 'test@example.invalid']);
    commit('Existing history without a prefix');
    base = git(['rev-parse', 'HEAD']);
  });
  tearDown(() => root.deleteSync(recursive: true));

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

  test(
    'rejects malformed subjects and accepts scopes and breaking markers',
    () {
      for (final subject in [
        'fix: save the curve',
        'feat(fans)!: replace presets',
        'chore!: require the new compiler',
        'revert: restore the previous preset',
      ]) {
        expect(conventionalSubject.hasMatch(subject), isTrue, reason: subject);
      }
      for (final subject in [
        'update: save the curve',
        'Fix: save the curve',
        'fix(): save the curve',
        'fix:no space',
        'fix: ',
        'fix:  ',
        'fix: description\nsecond line',
      ]) {
        expect(conventionalSubject.hasMatch(subject), isFalse, reason: subject);
      }
    },
  );

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
    final result = Process.runSync('dart', [
      script,
      base,
      git(['rev-parse', 'HEAD']),
    ], workingDirectory: root.path);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('Missing type'));
  });
}
