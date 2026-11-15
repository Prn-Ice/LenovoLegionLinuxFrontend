import 'dart:io';

import 'host_command_environment.dart';

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
    Future<String> Function()? pathResolver,
    ProcessRunner? processRunner,
  }) : _cliPath = cliPath,
       _pathResolver = pathResolver ?? (() async => _resolveInstalledCliPath()),
       _processRunner = processRunner ?? _runHostCommand;

  String? _cliPath;
  final Future<String> Function() _pathResolver;
  final ProcessRunner _processRunner;
  Future<String>? _resolving;
  bool _closed = false;
  String? get cliPath => _cliPath;

  Future<String> resolvePath() async {
    if (_closed) throw StateError('CLI access is closed.');
    final path = _cliPath ?? await (_resolving ??= _pathResolver());
    if (_closed) throw StateError('CLI access is closed.');
    if (path.isEmpty) throw StateError('The installed CLI path is empty.');
    _cliPath = path;
    return path;
  }

  void close() => _closed = true;

  static Future<ProcessResult> _runHostCommand(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: '/',
      environment: hostCommandEnvironment(Platform.environment),
      includeParentEnvironment: false,
    );
  }

  Future<LegionCliResult> runCommand(List<String> args) async {
    final cliArgs = _withHwmonExpectation(args);

    final path = await resolvePath();
    final result = await _processRunner(path, cliArgs);

    return LegionCliResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
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
