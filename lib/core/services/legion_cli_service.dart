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
    final executable = privileged ? 'pkexec' : _cliPath;
    final commandArgs = privileged ? [_cliPath, ...args] : args;

    final result = await Process.run(executable, commandArgs);

    return LegionCliResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }

  static String _resolveCliPath() {
    return _resolveInstalledCliPath();
  }

  static String _resolveInstalledCliPath() {
    try {
      final result = Process.runSync('which', ['legion_cli']);
      if (result.exitCode != 0) {
        throw StateError('legion_cli is required but was not found in PATH.');
      }

      final path = '${result.stdout}'.trim();
      if (path.isEmpty) {
        throw StateError('legion_cli is required but path resolution failed.');
      }

      return path;
    } on ProcessException catch (error) {
      throw StateError('Failed to locate legion_cli: ${error.message}');
    }
  }
}
