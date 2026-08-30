import 'dart:io';

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

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
  LegionCliService({
    String? cliPath,
    String? privilegedExecutable,
    ProcessRunner? processRunner,
  }) : _cliPath = cliPath ?? _resolveCliPath(),
       _privilegedExecutable =
           privilegedExecutable ?? _resolvePrivilegedExecutable(),
       _processRunner = processRunner ?? Process.run;

  final String _cliPath;
  final String _privilegedExecutable;
  final ProcessRunner _processRunner;
  String get cliPath => _cliPath;
  String get privilegedExecutable => _privilegedExecutable;

  Future<LegionCliResult> runCommand(
    List<String> args, {
    bool privileged = false,
  }) async {
    final executable = privileged ? _privilegedExecutable : _cliPath;
    final cliArgs = _withHwmonExpectation(args);
    final commandArgs = privileged ? [_cliPath, ...cliArgs] : cliArgs;

    final result = await _processRunner(executable, commandArgs);

    return LegionCliResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }

  static String _resolveCliPath() {
    return _resolveInstalledCliPath();
  }

  static String _resolvePrivilegedExecutable() {
    const nixosWrapper = '/run/wrappers/bin/pkexec';
    return File(nixosWrapper).existsSync() ? nixosWrapper : 'pkexec';
  }

  static List<String> _withHwmonExpectation(List<String> args) {
    const hwmonCommandPrefixes = [
      'fancurve-',
      'minifancurve-',
      'lockfancontroller-',
      'maximumfanspeed-',
    ];
    if (args.isEmpty ||
        args.contains('--donotexpecthwmon') ||
        hwmonCommandPrefixes.any(args.first.startsWith)) {
      return args;
    }
    return ['--donotexpecthwmon', ...args];
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
