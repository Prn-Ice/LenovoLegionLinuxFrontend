import 'dart:async';
import 'dart:collection';

import '../models/bridge_command_record.dart';
import 'legion_cli_service.dart';
import 'legion_control_client.dart';

enum LegionBridgeErrorCode {
  permissionDenied,
  privilegeSetup,
  unavailable,
  busy,
  timeout,
  graphicsBlocked,
  graphicsPending,
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

  String get guidance {
    return switch (code) {
      LegionBridgeErrorCode.permissionDenied =>
        'Permission was denied or authentication was canceled. Ensure a polkit agent is running and approve the prompt.',
      LegionBridgeErrorCode.privilegeSetup =>
        'The legion-control service could not provide privileged access. Verify the service and its Polkit policy are installed and running.',
      LegionBridgeErrorCode.unavailable =>
        'The legion-control service or requested capability is unavailable. Verify the service is installed and running.',
      LegionBridgeErrorCode.busy =>
        'Another privileged action is still running. Wait for it to finish, then retry.',
      LegionBridgeErrorCode.timeout =>
        'The privileged command timed out. Retry and check system load or blocking prompts.',
      LegionBridgeErrorCode.graphicsBlocked =>
        'The graphics change was blocked before firmware changed. Close dGPU clients or use the controlled TTY workflow, then retry.',
      LegionBridgeErrorCode.graphicsPending =>
        'The selected graphics policy may have changed, but effective topology did not settle. Restore Hybrid from a TTY or reboot before continuing.',
      LegionBridgeErrorCode.commandFailed => '',
    };
  }

  String get details {
    final values = [
      if (guidance.isNotEmpty) guidance,
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
  LegionFrontendBridgeService({
    required LegionCliService cliService,
    LegionControlClient? controlClient,
  }) : _cliService = cliService,
       _controlClient = controlClient;

  final LegionCliService _cliService;
  final LegionControlClient? _controlClient;
  final Set<String> _pendingActionKeys = <String>{};
  Future<void> _privilegedQueue = Future<void>.value();
  static const int _historyCapacity = 20;
  final ListQueue<BridgeCommandRecord> _history =
      ListQueue<BridgeCommandRecord>(_historyCapacity);

  /// The last [_historyCapacity] bridge commands in chronological order.
  List<BridgeCommandRecord> get commandHistory => List.unmodifiable(_history);

  bool isActionPending({required String method, required List<String> args}) {
    final actionKey = _buildActionKey(method: method, args: args);
    return _pendingActionKeys.contains(actionKey);
  }

  Future<void> runPrivilegedCommand({
    required String method,
    required List<String> args,
    Duration timeout = const Duration(seconds: 15),
    int retries = 0,
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

    final start = DateTime.now();
    var succeeded = false;
    try {
      await completion.future;
      succeeded = true;
    } finally {
      _recordHistory(
        method: method,
        args: args,
        isPrivileged: true,
        succeeded: succeeded,
        start: start,
      );
    }
  }

  Future<LegionCliResult> runCommand({
    required String method,
    required List<String> args,
    Duration timeout = const Duration(seconds: 5),
    int retries = 0,
    bool detectUnavailableResponse = false,
  }) async {
    final start = DateTime.now();
    var succeeded = false;
    try {
      final result = await _runCommand(
        method: method,
        args: args,
        timeout: timeout,
        retries: retries,
        privileged: false,
        detectUnavailableResponse: detectUnavailableResponse,
      );
      succeeded = true;
      return result;
    } finally {
      _recordHistory(
        method: method,
        args: args,
        isPrivileged: false,
        succeeded: succeeded,
        start: start,
      );
    }
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
        final result = privileged
            ? await _runControlCommand(method, args)
                  .timeout(timeout)
                  .then(
                    (_) => const LegionCliResult(
                      exitCode: 0,
                      stdout: '',
                      stderr: '',
                    ),
                  )
            : await _cliService.runCommand(args).timeout(timeout);

        final unavailable =
            !privileged &&
            detectUnavailableResponse &&
            _looksUnavailable(result);

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
      } on LegionControlException catch (error) {
        final translated = _translateControlError(method, error);
        if (attempt <= retries &&
            (translated.code == LegionBridgeErrorCode.busy ||
                translated.code == LegionBridgeErrorCode.timeout)) {
          continue;
        }
        throw translated;
      } on Object catch (error) {
        throw LegionBridgeException(
          code: LegionBridgeErrorCode.commandFailed,
          method: method,
          message: 'Failed to run $method.',
          stderr: '$error',
        );
      }
    }
  }

  Future<void> _runControlCommand(String method, List<String> args) {
    final client = _controlClient;
    if (client == null) {
      throw const LegionControlSetupException(
        'The legion-control service is not configured.',
      );
    }
    return client.runCommand(args);
  }

  LegionBridgeException _translateControlError(
    String method,
    LegionControlException error,
  ) {
    final code = switch (error) {
      LegionControlSetupException() => LegionBridgeErrorCode.privilegeSetup,
      LegionControlPermissionDeniedException() =>
        LegionBridgeErrorCode.permissionDenied,
      LegionControlBusyException() => LegionBridgeErrorCode.busy,
      LegionControlTimeoutException() => LegionBridgeErrorCode.timeout,
      LegionControlGraphicsBlockedException() =>
        LegionBridgeErrorCode.graphicsBlocked,
      LegionControlGraphicsPendingException() =>
        LegionBridgeErrorCode.graphicsPending,
      LegionControlUnavailableException() ||
      LegionControlNotSupportedException() => LegionBridgeErrorCode.unavailable,
      _ => LegionBridgeErrorCode.commandFailed,
    };
    return LegionBridgeException(
      code: code,
      method: method,
      message: 'Failed to run $method.',
      stderr: error.message,
    );
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
      LegionBridgeErrorCode.privilegeSetup =>
        'Privileged command support is unavailable for $method.',
      LegionBridgeErrorCode.unavailable =>
        'Capability is unavailable for $method.',
      LegionBridgeErrorCode.busy => 'System is busy while running $method.',
      LegionBridgeErrorCode.timeout => 'Timed out while running $method.',
      LegionBridgeErrorCode.graphicsBlocked =>
        'Graphics clients blocked $method before firmware changed.',
      LegionBridgeErrorCode.graphicsPending =>
        'Graphics topology did not settle while running $method.',
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
        outputLower.contains('authorization failed') ||
        outputLower.contains('authentication failed') ||
        outputLower.contains('authentication canceled') ||
        outputLower.contains('authentication cancelled') ||
        outputLower.contains('authentication is needed') ||
        outputLower.contains('permission denied') ||
        outputLower.contains('polkit')) {
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

  void _recordHistory({
    required String method,
    required List<String> args,
    required bool isPrivileged,
    required bool succeeded,
    required DateTime start,
  }) {
    final record = BridgeCommandRecord(
      timestamp: start,
      method: method,
      args: args,
      isPrivileged: isPrivileged,
      succeeded: succeeded,
      durationMs: DateTime.now().difference(start).inMilliseconds,
    );
    if (_history.length >= _historyCapacity) {
      _history.removeFirst();
    }
    _history.addLast(record);
  }
}
