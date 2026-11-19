import 'dart:io';

/// Owns the Git environment used to write a disposable test repository.
class GitFixture {
  GitFixture(this.root) {
    final home = Directory('${temporary.path}/home')..createSync();
    final config = Directory('${temporary.path}/config')..createSync();
    final empty = Directory('${temporary.path}/empty')..createSync();
    environment = {
      for (final entry in Platform.environment.entries)
        if (!entry.key.startsWith('GIT_')) entry.key: entry.value,
      'HOME': home.path,
      'XDG_CONFIG_HOME': config.path,
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_CONFIG_GLOBAL': '/dev/null',
      'GIT_TEMPLATE_DIR': empty.path,
    };
  }

  final Directory root;
  final temporary = Directory.systemTemp.createTempSync('git-fixture-');
  late final Map<String, String> environment;

  void initialize({String name = 'Fixture test'}) {
    root.createSync(recursive: true);
    git(['init', '-q', '--initial-branch=main']);
    for (final entry in {
      'user.name': name,
      'user.email': 'test@example.invalid',
      'core.hooksPath': '${temporary.path}/empty',
      'core.attributesFile': '/dev/null',
      'core.excludesFile': '/dev/null',
      'core.fsmonitor': 'false',
      'commit.gpgsign': 'false',
      'tag.gpgsign': 'false',
    }.entries) {
      git(['config', '--local', entry.key, entry.value]);
    }
  }

  String git(List<String> arguments) {
    final result = Process.runSync(
      'git',
      arguments,
      workingDirectory: root.path,
      environment: environment,
      includeParentEnvironment: false,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'git',
        arguments,
        result.stderr.toString(),
        result.exitCode,
      );
    }
    return (result.stdout as String).trim();
  }

  void dispose() => temporary.deleteSync(recursive: true);
}
