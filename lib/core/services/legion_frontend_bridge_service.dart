import 'dart:async';
import 'dart:collection';

import '../models/bridge_command_record.dart';
import '../models/control_mode.dart';
import 'legion_cli_service.dart';
import 'legion_control_client.dart';

enum LegionBridgeErrorCode {
  permissionDenied,
  privilegeSetup,
  portableSetup,
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
    this.controlMode = ControlMode.installedService,
  });

  final LegionBridgeErrorCode code;
  final String method;
  final String message;
  final String? stdout;
  final String? stderr;
  final int? exitCode;
  final ControlMode controlMode;

  String get guidance {
    return switch (code) {
      LegionBridgeErrorCode.permissionDenied =>
        controlMode == ControlMode.temporaryHelper
            ? 'Permission was denied or authentication was cancelled. Check that a Polkit authentication agent is running, then reopen the app before trying again.'
            : 'Permission was denied or authentication was cancelled. Ensure a Polkit authentication agent is running and approve the prompt.',
      LegionBridgeErrorCode.portableSetup =>
        'Temporary hardware access could not start. Check the installed CLI and app files, then reopen the app.',
      LegionBridgeErrorCode.privilegeSetup =>
        'The legion-control service could not provide privileged access. Verify that the service and its Polkit policy are installed and running.',
      LegionBridgeErrorCode.unavailable =>
        controlMode == ControlMode.temporaryHelper
            ? 'Temporary hardware access is unavailable. Read the current settings and reopen the app before retrying.'
            : 'The legion-control service or requested capability is unavailable. Verify that the service is installed and running.',
      LegionBridgeErrorCode.busy =>
        'Another privileged action is still running. Wait for it to finish, then retry.',
      LegionBridgeErrorCode.timeout =>
        'The command timed out. Read the current settings before retrying.',
      LegionBridgeErrorCode.graphicsBlocked =>
        'The system blocked the graphics change before firmware changed. Close dGPU clients or use the controlled TTY workflow, then retry.',
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
    ControlMode controlMode = ControlMode.installedService,
  }) : _cliService = cliService,
       _controlClient = controlClient,
       _controlMode = controlMode;

  final LegionCliService _cliService;
  final LegionControlClient? _controlClient;
  final ControlMode _controlMode;
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

  /// Queues a typed control call. [args] are history and duplicate-key metadata,
  /// never executable commands. The timeout begins when the operation starts.
  /// A timed-out write closes control access; it requires a fresh app session.
  Future<void> runControlOperation({
    required Future<void> Function(LegionControlClient) operation,
    required String method,
    List<String> args = const [],
    Duration timeout = const Duration(seconds: 15),
    int retries = 0,
  }) async {
    if (retries < 0) {
      throw ArgumentError.value(retries, 'retries', 'must be >= 0');
    }
    args = List.unmodifiable(args);
    final actionKey = _buildActionKey(method: method, args: args);
    if (_pendingActionKeys.contains(actionKey)) {
      throw LegionBridgeException(
        controlMode: _controlMode,
        code: LegionBridgeErrorCode.busy,
        method: method,
        message: 'Action is already pending for $method.',
      );
    }

    _pendingActionKeys.add(actionKey);
    final completion = Completer<void>();

    _privilegedQueue = _privilegedQueue.catchError((_) {}).then((_) async {
      try {
        await _runControlOperation(
          operation: operation,
          method: method,
          timeout: timeout,
          retries: retries,
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
    required bool detectUnavailableResponse,
  }) async {
    if (retries < 0) {
      throw ArgumentError.value(retries, 'retries', 'must be >= 0');
    }

    var attempt = 0;
    while (true) {
      attempt += 1;
      try {
        final result = await _cliService.runCommand(args).timeout(timeout);

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
          controlMode: _controlMode,
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
        throw _translateControlError(method, error);
      } on LegionBridgeException {
        rethrow;
      } on Object catch (error) {
        throw LegionBridgeException(
          controlMode: _controlMode,
          code: LegionBridgeErrorCode.commandFailed,
          method: method,
          message: 'Failed to run $method.',
          stderr: '$error',
        );
      }
    }
  }

  Future<void> _runControlOperation({
    required Future<void> Function(LegionControlClient) operation,
    required String method,
    required Duration timeout,
    required int retries,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final LegionBridgeException failure;
      try {
        final client = _controlClient;
        if (client == null) {
          throw const LegionControlSetupException(
            'The legion-control service is not configured.',
          );
        }
        await client.authorize();
        await operation(client).timeout(timeout);
        return;
      } on TimeoutException {
        failure = LegionBridgeException(
          controlMode: _controlMode,
          code: LegionBridgeErrorCode.timeout,
          method: method,
          message: 'Timed out while running $method.',
          stderr: 'Control access was closed. Restart the app before retrying.',
        );
      } on LegionControlException catch (error) {
        failure = _translateControlError(method, error);
      } catch (error) {
        failure = LegionBridgeException(
          controlMode: _controlMode,
          code: LegionBridgeErrorCode.commandFailed,
          method: method,
          message: 'Failed to run $method.',
          stderr: '$error',
        );
      }
      if (failure.code == LegionBridgeErrorCode.timeout) {
        await _controlClient?.close();
        throw failure;
      }
      if (attempt >= retries || failure.code != LegionBridgeErrorCode.busy) {
        throw failure;
      }
    }
  }

  LegionBridgeException _translateControlError(
    String method,
    LegionControlException error,
  ) {
    final code = switch (error) {
      LegionControlPortableSetupException() =>
        LegionBridgeErrorCode.portableSetup,
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
      controlMode: _controlMode,
      code: code,
      method: method,
      message: code == LegionBridgeErrorCode.timeout
          ? 'Control access timed out. Restart the app before retrying.'
          : 'Failed to run $method.',
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
      LegionBridgeErrorCode.portableSetup =>
        'Temporary hardware access could not start for $method.',
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
      controlMode: _controlMode,
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
