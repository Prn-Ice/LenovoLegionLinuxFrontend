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
  LegionCliService({String? cliPath, ProcessRunner? processRunner})
    : _cliPath = cliPath ?? _resolveCliPath(),
      _processRunner = processRunner ?? Process.run;

  final String _cliPath;
  final ProcessRunner _processRunner;
  String get cliPath => _cliPath;

  Future<LegionCliResult> runCommand(List<String> args) async {
    final cliArgs = _withHwmonExpectation(args);

    final result = await _processRunner(_cliPath, cliArgs);

    return LegionCliResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }

  static String _resolveCliPath() {
    return _resolveInstalledCliPath();
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
