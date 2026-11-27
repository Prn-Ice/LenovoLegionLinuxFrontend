import 'dart:io';

final _repositoryVariables = _readRepositoryVariables();

Set<String> _readRepositoryVariables() {
  final result = Process.runSync('git', ['rev-parse', '--local-env-vars']);
  if (result.exitCode != 0) {
    throw StateError('Cannot read Git environment names: ${result.stderr}');
  }
  return (result.stdout as String).trim().split('\n').toSet();
}

/// Keeps Git pointed at the caller's explicit repository, even inside a hook.
/// User configuration and credentials remain available for normal tool use.
Map<String, String> gitRepositoryEnvironment() =>
    Map<String, String>.of(Platform.environment)..removeWhere(
      (name, _) =>
          _repositoryVariables.contains(name) ||
          name.startsWith('GIT_CONFIG_KEY_') ||
          name.startsWith('GIT_CONFIG_VALUE_'),
    );
