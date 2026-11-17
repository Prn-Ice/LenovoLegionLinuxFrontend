import 'dart:convert';
import 'dart:io';

final conventionalSubject = RegExp(
  r'^(feat|fix|perf|refactor|docs|test|build|ci|chore|style|revert)'
  r'(\([^()\r\n]+\))?!?: \S[^\r\n]*$',
);

List<String> invalidCommitSubjects(Directory root, String base, String head) {
  final commitId = RegExp(r'^[0-9a-f]{40}$');
  if (!commitId.hasMatch(base) || !commitId.hasMatch(head)) {
    throw const FormatException('Expected full base and head commit hashes.');
  }
  final result = Process.runSync('git', [
    '-C',
    root.path,
    'log',
    '--no-merges',
    '--format=%h %s',
    '$base..$head',
    '--',
  ]);
  if (result.exitCode != 0) {
    throw StateError('Cannot read the PR commits: ${result.stderr}');
  }
  return const LineSplitter().convert(result.stdout as String).where((line) {
    final subject = line.substring(line.indexOf(' ') + 1);
    return !conventionalSubject.hasMatch(subject);
  }).toList();
}

void main(List<String> args) {
  try {
    if (args.length != 2) {
      throw const FormatException(
        'Usage: dart tool/check_commits.dart BASE_SHA HEAD_SHA',
      );
    }
    final invalid = invalidCommitSubjects(Directory.current, args[0], args[1]);
    if (invalid.isNotEmpty) {
      stderr.writeln(
        'Use type(scope): description for these commits. '
        'See CONTRIBUTING.md for allowed types.\n${invalid.join('\n')}',
      );
      exitCode = 1;
    }
  } catch (error) {
    stderr.writeln('Commit check: $error');
    exitCode = 1;
  }
}
