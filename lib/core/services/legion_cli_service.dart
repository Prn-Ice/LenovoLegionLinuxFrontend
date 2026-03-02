import 'dart:io';

class LegionCliResult {
  const LegionCliResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;
}

class LegionCliService {
  LegionCliService({String? cliPath}) : _cliPath = cliPath ?? _resolveCliPath();

  final String _cliPath;
  String get cliPath => _cliPath;

  Future<LegionCliResult> runCommand(
    List<String> args, {
    bool privileged = false,
  }) async {
    final executable = privileged ? 'pkexec' : 'python3';
    final commandArgs = privileged
        ? ['python3', _cliPath, ...args]
        : [_cliPath, ...args];

    final result = await Process.run(executable, commandArgs);

    return LegionCliResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }

  static String _resolveCliPath() {
    final candidates = [
      '${Directory.current.path}/../../python/legion_linux/legion_linux/legion_cli.py',
      '${Directory.current.path}/../python/legion_linux/legion_linux/legion_cli.py',
      '${Directory.current.path}/python/legion_linux/legion_linux/legion_cli.py',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }

    return candidates.first;
  }
}
