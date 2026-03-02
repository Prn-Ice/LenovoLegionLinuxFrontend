import 'dart:async';

import 'legion_cli_service.dart';

enum LegionBridgeErrorCode {
  permissionDenied,
  unavailable,
  busy,
  timeout,
  commandFailed,
}

class LegionBridgeException implements Exception {
  const LegionBridgeException({
    required this.code,
    required this.method,
    required this.message,
    this.stdout,
    this.stderr,
    this.exitCode,
  });

  final LegionBridgeErrorCode code;
  final String method;
  final String message;
  final String? stdout;
  final String? stderr;
  final int? exitCode;

  String get details {
    final values = [
      if (stderr != null && stderr!.trim().isNotEmpty) stderr!.trim(),
      if (stdout != null && stdout!.trim().isNotEmpty) stdout!.trim(),
    ];
    return values.join('\n');
  }

  @override
  String toString() {
    final detail = details;
    if (detail.isEmpty) {
      return message;
    }
    return '$message: $detail';
  }
}

class LegionFrontendBridgeService {
  LegionFrontendBridgeService({required LegionCliService cliService})
    : _cliService = cliService;

  final LegionCliService _cliService;
  final Set<String> _pendingActionKeys = <String>{};
  Future<void> _privilegedQueue = Future<void>.value();

  bool isActionPending({required String method, required List<String> args}) {
    final actionKey = _buildActionKey(method: method, args: args);
    return _pendingActionKeys.contains(actionKey);
  }

  Future<void> runPrivilegedCommand({
    required String method,
    required List<String> args,
    Duration timeout = const Duration(seconds: 5),
    int retries = 1,
    bool detectUnavailableResponse = true,
  }) async {
    final actionKey = _buildActionKey(method: method, args: args);
    if (_pendingActionKeys.contains(actionKey)) {
      throw LegionBridgeException(
        code: LegionBridgeErrorCode.busy,
        method: method,
        message: 'Action is already pending for $method.',
      );
    }

    _pendingActionKeys.add(actionKey);
    final completion = Completer<void>();

    _privilegedQueue = _privilegedQueue.catchError((_) {}).then((_) async {
      try {
        await _runCommand(
          method: method,
          args: args,
          timeout: timeout,
          retries: retries,
          privileged: true,
          detectUnavailableResponse: detectUnavailableResponse,
        );
        completion.complete();
      } catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
      } finally {
        _pendingActionKeys.remove(actionKey);
      }
    });

    await completion.future;
  }

  Future<LegionCliResult> runCommand({
    required String method,
    required List<String> args,
    Duration timeout = const Duration(seconds: 5),
    int retries = 0,
    bool privileged = false,
    bool detectUnavailableResponse = false,
  }) async {
    return _runCommand(
      method: method,
      args: args,
      timeout: timeout,
      retries: retries,
      privileged: privileged,
      detectUnavailableResponse: detectUnavailableResponse,
    );
  }

  Future<LegionCliResult> _runCommand({
    required String method,
    required List<String> args,
    required Duration timeout,
    required int retries,
    required bool privileged,
    required bool detectUnavailableResponse,
  }) async {
    if (retries < 0) {
      throw ArgumentError.value(retries, 'retries', 'must be >= 0');
    }

    var attempt = 0;
    while (true) {
      attempt += 1;
      try {
        final result = await _cliService
            .runCommand(args, privileged: privileged)
            .timeout(timeout);

        final unavailable =
            detectUnavailableResponse && _looksUnavailable(result);

        if (result.ok && !unavailable) {
          return result;
        }

        final error = _buildCommandFailure(method, result, unavailable);
        final shouldRetry =
            attempt <= retries &&
            (error.code == LegionBridgeErrorCode.busy ||
                error.code == LegionBridgeErrorCode.timeout);
        if (shouldRetry) {
          continue;
        }

        throw error;
      } on TimeoutException {
        final error = LegionBridgeException(
          code: LegionBridgeErrorCode.timeout,
          method: method,
          message: 'Timed out while running $method.',
        );

        final shouldRetry = attempt <= retries;
        if (shouldRetry) {
          continue;
        }

        throw error;
      }
    }
  }

  LegionBridgeException _buildCommandFailure(
    String method,
    LegionCliResult result,
    bool forcedUnavailable,
  ) {
    final outputLower = '${result.stdout}\n${result.stderr}'.toLowerCase();

    final code = forcedUnavailable
        ? LegionBridgeErrorCode.unavailable
        : _classifyFailureCode(outputLower, result.exitCode);

    final message = switch (code) {
      LegionBridgeErrorCode.permissionDenied =>
        'Permission denied while running $method.',
      LegionBridgeErrorCode.unavailable =>
        'Capability is unavailable for $method.',
      LegionBridgeErrorCode.busy => 'System is busy while running $method.',
      LegionBridgeErrorCode.timeout => 'Timed out while running $method.',
      LegionBridgeErrorCode.commandFailed => 'Failed to run $method.',
    };

    return LegionBridgeException(
      code: code,
      method: method,
      message: message,
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
    );
  }

  LegionBridgeErrorCode _classifyFailureCode(String outputLower, int exitCode) {
    if (exitCode == 126 ||
        outputLower.contains('not authorized') ||
        outputLower.contains('authentication is needed') ||
        outputLower.contains('permission denied') ||
        outputLower.contains('pkexec')) {
      return LegionBridgeErrorCode.permissionDenied;
    }

    if (exitCode == 127 ||
        outputLower.contains('command not found') ||
        outputLower.contains('command not available') ||
        outputLower.contains('not supported') ||
        outputLower.contains('unsupported')) {
      return LegionBridgeErrorCode.unavailable;
    }

    if (outputLower.contains('busy') ||
        outputLower.contains('resource temporarily unavailable')) {
      return LegionBridgeErrorCode.busy;
    }

    return LegionBridgeErrorCode.commandFailed;
  }

  bool _looksUnavailable(LegionCliResult result) {
    final outputLower = '${result.stdout}\n${result.stderr}'.toLowerCase();
    return outputLower.contains('command not available') ||
        outputLower.contains('not supported') ||
        outputLower.contains('unsupported');
  }

  String _buildActionKey({required String method, required List<String> args}) {
    final serializedArgs = args.join('\u0000');
    return '$method\u0000$serializedArgs';
  }
}
