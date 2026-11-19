import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'control_commands.dart';
import 'linux_resources.dart';
import 'managed_command.dart';

/// Methods exposed by the control protocol.
enum ControlMethod {
  getCapabilities,
  authorize,
  requestGraphicsModeAtBoot,
  cancelGraphicsModeAtBoot,
  getGraphicsBootRequest,
  setFeature,
  setToggle,
  setGraphicsMode,
  applyFanPreset,
  applyCurrentFanPreset,
  applyFanCurve,
  applyCustomConservation,
  setBootLogo,
  restoreBootLogo,
  setServiceEnabled,
}

class ControlRequest {
  ControlRequest(this.method, [List<Object> arguments = const []])
    : arguments = List<Object>.unmodifiable(arguments);

  final ControlMethod method;
  final List<Object> arguments;
}

class ControlReply {
  const ControlReply.success([this.values = const []])
    : errorName = null,
      errorMessage = null;
  const ControlReply.error(this.errorName, this.errorMessage)
    : values = const [];

  final List<Object> values;
  final String? errorName;
  final String? errorMessage;
  bool get isSuccess => errorName == null;
}

typedef ExecuteCommand = ManagedCommandOperation Function(
  String executable,
  List<String> arguments,
  int runtimeSeconds,
);

class ControlDispatcher {
  ControlDispatcher({
    required this.execute,
    required this.cli,
    required this.sessionDirectory,
    LinuxResources? resources,
  }) : resources = resources ?? LinuxResources();

  final ExecuteCommand execute;
  final String cli;
  final Directory sessionDirectory;
  final LinuxResources resources;
  bool _authorized = false;
  bool _cleanupFailed = false;
  ManagedCommandOperation? _active;
  Completer<void>? _activeDone;
  bool get active => _active != null;
  bool _closed = false;

  /// Entry point for the sd-bus adapter. The adapter keeps transport details out
  /// of this class and passes decoded method values unchanged.
  Future<ControlReply> call(String method, List<Object> values) {
    final parsed = _methodNames[method];
    if (parsed == null) {
      return Future.value(
        const ControlReply.error('InvalidArgs', 'unknown method'),
      );
    }
    return dispatch(ControlRequest(parsed, values));
  }

  Future<ControlReply> dispatch(ControlRequest request) async {
    if (_closed) {
      return const ControlReply.error('Unavailable', 'session closed');
    }
    if (request.method == ControlMethod.getCapabilities) {
      return ControlReply.success([
        1,
        <String>['interactive-control'],
      ]);
    }
    if (request.method == ControlMethod.authorize) {
      _authorized = true;
      return const ControlReply.success();
    }
    if (!_authorized) {
      return const ControlReply.error(
        'org.freedesktop.DBus.Error.AccessDenied',
        'Authorize must be called first',
      );
    }
    if (const {
      ControlMethod.setServiceEnabled,
      ControlMethod.requestGraphicsModeAtBoot,
      ControlMethod.cancelGraphicsModeAtBoot,
      ControlMethod.getGraphicsBootRequest,
    }.contains(request.method)) {
      return const ControlReply.error(
        'NotSupported',
        'this operation requires installed system integration',
      );
    }
    if (_cleanupFailed) {
      return const ControlReply.error(
        'Unavailable',
        'command runner unavailable; restart the control service',
      );
    }
    try {
      return await _dispatchAuthorized(request);
    } on FormatException catch (error) {
      return ControlReply.error('InvalidArgs', error.message);
    } on _PayloadException catch (error) {
      return ControlReply.error(error.name, error.message);
    }
  }

  Future<ControlReply> _dispatchAuthorized(ControlRequest request) async {
    final built = _buildCommand(request);
    if (built == null) {
      return const ControlReply.error('InvalidArgs', 'unknown method');
    }
    if (_active != null) {
      if (!built.cleanup()) _cleanupFailed = true;
      return const ControlReply.error(
        'Busy',
        'another control operation is running',
      );
    }
    late final ManagedCommandOperation operation;
    try {
      operation = execute(
        built.executable,
        built.arguments,
        built.timeout.inSeconds,
      );
    } on Object {
      if (!built.cleanup()) _cleanupFailed = true;
      return const ControlReply.error(
        'Unavailable',
        'command runner could not start the operation',
      );
    }
    _active = operation;
    _activeDone = Completer<void>();
    try {
      try {
        try {
          final result = await operation.result;
          return _replyFor(result, built);
        } on Object catch (error) {
          return ControlReply.error(
            'Unavailable',
            'command runner failed: $error',
          );
        }
      } finally {
        if (!built.cleanup()) _cleanupFailed = true;
      }
    } finally {
      _active = null;
      _activeDone?.complete();
      _activeDone = null;
    }
  }

  ControlReply _replyFor(ManagedCommandResult result, _BuiltCommand command) {
    if (_closed) {
      return const ControlReply.error('Unavailable', 'session ended');
    }
    if (result.status == ManagedCommandStatus.cleanupFailed) {
      _cleanupFailed = true;
      return const ControlReply.error(
        'Unavailable',
        'backend cleanup could not be confirmed; restart the control service',
      );
    }
    switch (result.status) {
      case ManagedCommandStatus.success:
        return const ControlReply.success();
      case ManagedCommandStatus.unavailable:
        return ControlReply.error('Unavailable', result.error);
      case ManagedCommandStatus.busy:
        return ControlReply.error('Busy', result.error);
      case ManagedCommandStatus.timeout:
        return const ControlReply.error(
          'Timeout',
          'control operation timed out',
        );
      case ManagedCommandStatus.outputLimit:
        return const ControlReply.error(
          'CommandFailed',
          'backend output exceeded limit',
        );
      case ManagedCommandStatus.commandFailed:
        final output = utf8.decode(result.output, allowMalformed: true);
        if (command.graphics &&
            classifyBackendExit(BackendCategory.graphics, result.exitStatus) ==
                BackendOutcome.graphicsBlocked) {
          return ControlReply.error(
            'GraphicsBlocked',
            output.isEmpty
                ? 'graphics change was blocked before write'
                : output,
          );
        }
        if (command.graphics &&
            classifyBackendExit(BackendCategory.graphics, result.exitStatus) ==
                BackendOutcome.graphicsPending) {
          return ControlReply.error(
            'GraphicsPending',
            output.isEmpty
                ? 'graphics policy changed but topology did not settle'
                : output,
          );
        }
        final outcome = classifyBackendExit(
          BackendCategory.cli,
          result.exitStatus,
        );
        if (outcome == BackendOutcome.unavailable) {
          return ControlReply.error(
            'Unavailable',
            'backend capability is unavailable${output.isEmpty ? '' : ': $output'}',
          );
        }
        if (outcome == BackendOutcome.notSupported) {
          return ControlReply.error(
            'NotSupported',
            'backend feature is not supported${output.isEmpty ? '' : ': $output'}',
          );
        }
        return ControlReply.error(
          'CommandFailed',
          output.isEmpty
              ? 'backend command failed'
              : 'backend command failed: $output',
        );
      case ManagedCommandStatus.cleanupFailed:
        return const ControlReply.error(
          'Unavailable',
          'backend cleanup could not be confirmed; restart the control service',
        );
    }
  }

  _BuiltCommand? _buildCommand(ControlRequest request) {
    final a = request.arguments;
    switch (request.method) {
      case ControlMethod.setFeature:
        _checkCount(a, 2);
        return _BuiltCommand(
          cli,
          buildFeatureCommandFromText(_string(a[0]), _string(a[1])).arguments,
        );
      case ControlMethod.setToggle:
        _checkCount(a, 2);
        return _BuiltCommand(
          cli,
          buildToggleCommand(
            parseCapability(_string(a[0])),
            _bool(a[1]),
          ).arguments,
        );
      case ControlMethod.setGraphicsMode:
        _checkCount(a, 1);
        return _BuiltCommand(
          cli,
          buildGraphicsModeCommand(parseGraphicsMode(_string(a[0]))).arguments,
          graphics: true,
        );
      case ControlMethod.applyFanPreset:
        _checkCount(a, 1);
        return _BuiltCommand(
          cli,
          buildPresetCommand(parseFanPreset(_string(a[0]))).arguments,
        );
      case ControlMethod.applyCurrentFanPreset:
        _checkCount(a, 0);
        return _BuiltCommand(cli, buildCurrentPresetCommand().arguments);
      case ControlMethod.applyCustomConservation:
        _checkCount(a, 2);
        return _BuiltCommand(
          cli,
          buildConservationCommand(_int(a[0]), _int(a[1])).arguments,
        );
      case ControlMethod.restoreBootLogo:
        _checkCount(a, 0);
        return _BuiltCommand(cli, buildRestoreBootLogoCommand().arguments);
      case ControlMethod.requestGraphicsModeAtBoot:
      case ControlMethod.cancelGraphicsModeAtBoot:
      case ControlMethod.getGraphicsBootRequest:
        return null;
      case ControlMethod.applyFanCurve:
        _checkCount(a, 1);
        return _payloadCommand(
          a[0],
          fanCurvePayloadLimit,
          buildFanCurveFileCommand,
        );
      case ControlMethod.setBootLogo:
        _checkCount(a, 1);
        return _payloadCommand(
          a[0],
          bootLogoPayloadLimit,
          buildBootLogoCommand,
        );
      case ControlMethod.setServiceEnabled:
        return null;
      case ControlMethod.getCapabilities:
      case ControlMethod.authorize:
        return null;
    }
  }

  _BuiltCommand _payloadCommand(
    Object value,
    int limit,
    HelperCommand Function(File) builder,
  ) {
    if (value is! Uint8List && value is! List<int>) {
      throw const FormatException('payload must be bytes');
    }
    final source = value as List<int>;
    validatePayload(source, limit);
    final bytes = Uint8List.fromList(source);
    Directory? privateDirectory;
    try {
      privateDirectory = Directory(sessionDirectory.path)
          .createTempSync('legion-control-');
      resources.setMode(privateDirectory.path, 0x1c0); // 0700.
      final file = File('${privateDirectory.path}/payload');
      file.createSync(exclusive: true);
      resources.setMode(file.path, 0x180); // 0600, before writing.
      try {
        file.writeAsBytesSync(bytes, flush: true);
      } on FileSystemException catch (error) {
        throw _PayloadException('Unavailable', error.message);
      }
      return _BuiltCommand(
        cli,
        builder(file).arguments,
        payload: file,
        payloadDirectory: privateDirectory,
      );
    } on FileSystemException catch (error) {
      _deleteDirectory(privateDirectory);
      throw _PayloadException('Backend', error.message);
    } on Object {
      _deleteDirectory(privateDirectory);
      rethrow;
    }
  }

  Future<void> close() async {
    _closed = true;
    final operation = _active;
    if (operation != null) {
      operation.cancel();
      try {
        await operation.result;
      } catch (_) {
        // The runner owns cancellation cleanup; shutdown still waits for drain.
      }
      final done = _activeDone;
      if (done != null) await done.future;
    }
  }
}

void _deleteDirectory(Directory? directory) {
  try {
    directory?.deleteSync(recursive: true);
  } on FileSystemException {
    // Preserve the original payload error.
  }
}

const _methodNames = <String, ControlMethod>{
  'GetCapabilities': ControlMethod.getCapabilities,
  'Authorize': ControlMethod.authorize,
  'RequestGraphicsModeAtBoot': ControlMethod.requestGraphicsModeAtBoot,
  'CancelGraphicsModeAtBoot': ControlMethod.cancelGraphicsModeAtBoot,
  'GetGraphicsBootRequest': ControlMethod.getGraphicsBootRequest,
  'SetFeature': ControlMethod.setFeature,
  'SetToggle': ControlMethod.setToggle,
  'SetGraphicsMode': ControlMethod.setGraphicsMode,
  'ApplyFanPreset': ControlMethod.applyFanPreset,
  'ApplyCurrentFanPreset': ControlMethod.applyCurrentFanPreset,
  'ApplyFanCurve': ControlMethod.applyFanCurve,
  'ApplyCustomConservation': ControlMethod.applyCustomConservation,
  'SetBootLogo': ControlMethod.setBootLogo,
  'RestoreBootLogo': ControlMethod.restoreBootLogo,
  'SetServiceEnabled': ControlMethod.setServiceEnabled,
};

class _BuiltCommand {
  _BuiltCommand(
    this.executable,
    this.arguments, {
    this.graphics = false,
    this.payload,
    this.payloadDirectory,
  }) : timeout = graphics
           ? const Duration(seconds: 35)
           : const Duration(seconds: 10);
  final String executable;
  final List<String> arguments;
  final bool graphics;
  final Duration timeout;
  final File? payload;
  final Directory? payloadDirectory;

  bool cleanup() {
    try {
      payloadDirectory?.deleteSync(recursive: true);
      return true;
    } on FileSystemException {
      return false;
    }
  }
}

class _PayloadException implements Exception {
  const _PayloadException(this.name, this.message);
  final String name;
  final String message;
}

String _string(Object value) =>
    value is String ? value : (throw const FormatException('expected string'));
bool _bool(Object value) =>
    value is bool ? value : (throw const FormatException('expected boolean'));
int _int(Object value) =>
    value is int ? value : (throw const FormatException('expected integer'));
void _checkCount(List<Object> values, int count) {
  if (values.length != count) {
    throw const FormatException('invalid argument count');
  }
}
