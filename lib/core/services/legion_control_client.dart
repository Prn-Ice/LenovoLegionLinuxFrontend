import 'dart:async';

import 'package:dbus/dbus.dart';

import '../models/control_capabilities.dart';
import '../models/control_mode.dart';
import '../models/control_selectors.dart';
import '../../features/dgpu/models/graphics_mode.dart';

abstract class LegionControlTransport {
  Future<void> prepare() async {}
  Future<ControlCapabilities> getCapabilities();
  Future<void> authorize();
  Future<void> call(String method, List<Object> arguments);
  Future<void> close();
}

class LegionControlException implements Exception {
  const LegionControlException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LegionControlNotSupportedException extends LegionControlException {
  const LegionControlNotSupportedException(super.message);
}

class LegionControlPermissionDeniedException extends LegionControlException {
  const LegionControlPermissionDeniedException(super.message);
}

class LegionControlTimeoutException extends LegionControlException {
  const LegionControlTimeoutException(super.message);
}

class LegionControlCommandFailedException extends LegionControlException {
  const LegionControlCommandFailedException(super.message);
}

class LegionControlSetupException extends LegionControlUnavailableException {
  const LegionControlSetupException(super.message);
}

class LegionControlPortableSetupException extends LegionControlSetupException {
  const LegionControlPortableSetupException(super.message);
}

class LegionControlUnavailableException extends LegionControlException {
  const LegionControlUnavailableException(super.message);
}

class LegionControlBusyException extends LegionControlException {
  const LegionControlBusyException(super.message);
}

class LegionControlGraphicsBlockedException extends LegionControlException {
  const LegionControlGraphicsBlockedException(super.message);
}

class LegionControlGraphicsPendingException extends LegionControlException {
  const LegionControlGraphicsPendingException(super.message);
}

/// The production transport for the privileged legion-control system service.
class DBusLegionControlTransport extends LegionControlTransport {
  DBusLegionControlTransport({DBusClient? client})
    : _client =
          client ??
          DBusClient(DBusAddress('unix:path=/run/dbus/system_bus_socket'));

  static const _busName = 'io.github.prnice.LegionControl1';
  static const _setupTimeout = Duration(seconds: 5);
  final DBusClient _client;
  String? _owner;
  bool _closed = false;
  Future<void>? _closing;

  void _ensureOpen() {
    if (_closed) {
      throw const LegionControlUnavailableException(
        'Control service connection is closed. Restart the app to reconnect.',
      );
    }
  }

  Future<String?> _resolveOwner() async {
    try {
      return await _client.getNameOwner(_busName);
    } finally {
      // DBusClient may finish opening its socket after close() was called.
      if (_closed) await _client.close();
    }
  }

  Future<String> _destination() async {
    _ensureOpen();
    String? owner;
    try {
      owner = await _resolveOwner().timeout(_setupTimeout);
    } on TimeoutException {
      await close();
      throw const LegionControlTimeoutException(
        'Control service lookup timed out. Restart the app to reconnect.',
      );
    }
    _ensureOpen();
    if (_owner != null && owner != _owner) {
      await close();
      throw const LegionControlUnavailableException(
        'Control service restarted. Restart the app to check compatibility and reconnect.',
      );
    }
    if (owner == null) {
      throw const LegionControlSetupException(
        'The installed control service is unavailable. Start the legion-control service and retry.',
      );
    }
    _owner = owner;
    return owner;
  }

  Future<DBusMethodSuccessResponse> _invoke(
    String method, {
    Iterable<DBusValue> values = const [],
    DBusSignature? replySignature,
    bool allowInteractiveAuthorization = false,
  }) async {
    final destination = await _destination();
    _ensureOpen();
    final reply = await _client.callMethod(
      destination: destination,
      path: DBusObjectPath('/io/github/prnice/LegionControl1'),
      interface: _busName,
      name: method,
      values: values,
      noAutoStart: true,
      allowInteractiveAuthorization: allowInteractiveAuthorization,
      replySignature: replySignature ?? DBusSignature.empty,
    );
    _ensureOpen();
    return reply;
  }

  @override
  Future<ControlCapabilities> getCapabilities() async {
    final reply = await _invoke(
      'GetCapabilities',
      replySignature: DBusSignature('uas'),
    );
    final advertised = reply.returnValues[1].asStringArray().toSet();
    return ControlCapabilities(
      protocolVersion: reply.returnValues[0].asUint32(),
      supported: {
        if (advertised.contains('interactive-control'))
          ControlCapability.interactiveControl,
        if (advertised.contains('persistent-services'))
          ControlCapability.persistentServices,
        if (advertised.contains('next-boot-graphics'))
          ControlCapability.nextBootGraphics,
      },
    );
  }

  @override
  Future<void> authorize() async {
    await _invoke('Authorize', allowInteractiveAuthorization: true);
  }

  @override
  Future<void> call(String method, List<Object> arguments) async {
    _ensureOpen();
    final values = arguments.map((argument) {
      if (argument is String) return DBusString(argument);
      if (argument is bool) return DBusBoolean(argument);
      if (argument is int) return DBusUint32(argument);
      if (argument is List<int>) return DBusArray.byte(argument);
      throw ArgumentError.value(
        argument,
        'argument',
        'Unsupported D-Bus value',
      );
    });
    await _invoke(method, values: values);
  }

  @override
  Future<void> close() {
    _closed = true;
    return _closing ??= _client.close();
  }
}

/// Validates typed control operations against the D-Bus contract.
class LegionControlClient {
  LegionControlClient({
    required LegionControlTransport transport,
    this.controlMode = ControlMode.installedService,
    Duration authorizationTimeout = const Duration(minutes: 2),
    Duration metadataTimeout = const Duration(seconds: 5),
  }) : _transport = transport,
       _authorizationTimeout = authorizationTimeout,
       _metadataTimeout = metadataTimeout;

  final LegionControlTransport _transport;
  final ControlMode controlMode;
  final Duration _authorizationTimeout;
  final Duration _metadataTimeout;
  Future<void>? _preparing;
  Future<ControlCapabilities>? _capabilities;
  Future<void>? _authorization;
  Future<void>? _closing;
  bool _closed = false;
  final _ending = StreamController<LegionControlException>.broadcast(
    sync: true,
  );

  void _ensureOpen() {
    if (_closed) {
      throw const LegionControlUnavailableException(
        'Control connection is closed. Restart the app to reconnect.',
      );
    }
  }

  Future<T> _whileOpen<T>(Future<T> operation) async {
    final result = Completer<T>();
    final ending = _ending.stream.listen((error) {
      if (!result.isCompleted) result.completeError(error);
    });
    // Closing DBusClient does not settle its outstanding method calls.
    operation.then(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    try {
      return await result.future;
    } finally {
      await ending.cancel();
    }
  }

  /// Checks the selected helper's protocol before API authorization.
  Future<ControlCapabilities> getCapabilities() async {
    _ensureOpen();
    await (_preparing ??= _prepareConnection());
    _ensureOpen();
    final pending = _capabilities ??= _loadCapabilities();
    try {
      final capabilities = await pending;
      _ensureOpen();
      return capabilities;
    } catch (error) {
      if (identical(_capabilities, pending)) _capabilities = null;
      if (error is LegionControlSetupException) {
        await close();
        throw error is LegionControlPortableSetupException
            ? error
            : _setupError(error.message);
      }
      rethrow;
    }
  }

  Future<void> _prepareConnection() async {
    try {
      await _whileOpen(
        _transport.prepare(),
      ).timeout(const Duration(seconds: 125));
    } on TimeoutException {
      const error = LegionControlTimeoutException(
        'Control startup timed out. Start a new app session to retry.',
      );
      await _closeWith(error);
      throw error;
    } catch (error) {
      await close();
      if (error is LegionControlSetupException) {
        throw error is LegionControlPortableSetupException
            ? error
            : _setupError(error.message);
      }
      rethrow;
    }
  }

  LegionControlSetupException _setupError(String message) =>
      controlMode == ControlMode.temporaryHelper
      ? LegionControlPortableSetupException(message)
      : LegionControlSetupException(message);

  /// Obtains approval before the backend command's timeout starts.
  Future<void> authorize() async {
    await getCapabilities();
    await _authorizeOnce();
  }

  Future<void> _authorizeOnce() async {
    _ensureOpen();
    final authorization = _authorization ??= _transport.authorize();
    try {
      await _whileOpen(authorization).timeout(_authorizationTimeout);
      _ensureOpen();
    } on TimeoutException {
      const error = LegionControlTimeoutException(
        'Control authorization timed out. Start a new app session to retry.',
      );
      await _closeWith(error);
      throw error;
    } on DBusMethodResponseException catch (error) {
      if (identical(_authorization, authorization)) _authorization = null;
      throw _translateDbusError(error);
    } catch (_) {
      if (identical(_authorization, authorization)) _authorization = null;
      rethrow;
    }
  }

  Future<ControlCapabilities> _loadCapabilities() async {
    ControlCapabilities capabilities;
    try {
      capabilities = await _whileOpen(
        _transport.getCapabilities(),
      ).timeout(_metadataTimeout);
    } on DBusReplySignatureException {
      throw const LegionControlSetupException(
        'The control helper returned invalid compatibility information. Update the app and control helper together.',
      );
    } on DBusMethodResponseException catch (error) {
      if (error.errorName.endsWith('UnknownMethod') ||
          error.errorName.endsWith('UnknownInterface') ||
          error.errorName.endsWith('UnknownObject')) {
        throw const LegionControlSetupException(
          'The control helper cannot report compatibility. Update the app and control helper together.',
        );
      }
      throw _translateDbusError(error);
    } on TimeoutException {
      const error = LegionControlTimeoutException(
        'The control helper did not report compatibility in time. Restart the app and retry.',
      );
      await _closeWith(error);
      throw error;
    }
    if (capabilities.protocolVersion !=
        ControlCapabilities.currentProtocolVersion) {
      throw LegionControlSetupException(
        'Control protocol ${capabilities.protocolVersion} is incompatible with app protocol ${ControlCapabilities.currentProtocolVersion}. Update the app and control helper together.',
      );
    }
    if (!capabilities.supported.contains(
      ControlCapability.interactiveControl,
    )) {
      throw const LegionControlSetupException(
        'The selected control helper does not support interactive controls. Update the app and control helper together.',
      );
    }
    return capabilities;
  }

  Future<void> _call(
    String method,
    List<Object> arguments, {
    ControlCapability capability = ControlCapability.interactiveControl,
    bool retryAfterAuthorizationLoss = true,
  }) async {
    final capabilities = await getCapabilities();
    if (!capabilities.supported.contains(capability)) {
      throw const LegionControlNotSupportedException(
        'Changing system services requires installed system integration.',
      );
    }
    await _authorizeOnce();
    final authorization = _authorization;
    try {
      await _whileOpen(_transport.call(method, arguments));
    } on DBusMethodResponseException catch (error) {
      if (_isAuthorizationFailure(error)) {
        if (identical(_authorization, authorization)) _authorization = null;
        if (retryAfterAuthorizationLoss) {
          return _call(
            method,
            arguments,
            capability: capability,
            retryAfterAuthorizationLoss: false,
          );
        }
      }
      throw _translateDbusError(error);
    } catch (_) {
      if (identical(_authorization, authorization)) _authorization = null;
      rethrow;
    }
  }

  Future<void> setFeature(ControlFeature feature, String value) {
    _validateFeature(feature, value);
    return _call('SetFeature', [feature.wireValue, value]);
  }

  Future<void> setToggle(ControlToggle toggle, bool enabled) {
    return _call('SetToggle', [toggle.wireValue, enabled]);
  }

  Future<void> setGraphicsMode(GraphicsMode mode) {
    if (mode == GraphicsMode.hybridAuto) {
      _unsupported('Unsupported graphics mode.');
    }
    return _call('SetGraphicsMode', [mode.wireValue]);
  }

  Future<void> applyFanPreset(ControlFanPreset preset) {
    return _call('ApplyFanPreset', [preset.wireValue]);
  }

  Future<void> applyCurrentFanPreset() =>
      _call('ApplyCurrentFanPreset', const []);
  Future<void> applyFanCurve(List<int> bytes) {
    _validateBytes(bytes, 64 * 1024, 'fan curve');
    return _call('ApplyFanCurve', [bytes]);
  }

  Future<void> applyCustomConservation(int lower, int upper) {
    if (lower < 0 || upper < 0 || lower > 100 || upper > 100 || lower > upper) {
      _unsupported('Malformed conservation limits.');
    }
    return _call('ApplyCustomConservation', [lower, upper]);
  }

  Future<void> setBootLogo(List<int> bytes) {
    _validateBytes(bytes, 16 * 1024 * 1024, 'boot logo');
    return _call('SetBootLogo', [bytes]);
  }

  Future<void> restoreBootLogo() => _call('RestoreBootLogo', const []);
  Future<void> setServiceEnabled(ControlService service, bool enabled) => _call(
    'SetServiceEnabled',
    [service.wireValue, enabled],
    capability: ControlCapability.persistentServices,
  );

  Future<void> _closeWith(LegionControlException error) {
    if (!_closed) {
      _closed = true;
      _ending.add(error);
      unawaited(_ending.close());
    }
    return _closing ??= _transport.close();
  }

  Future<void> close() => _closeWith(
    const LegionControlUnavailableException(
      'Control connection is closed. Restart the app to reconnect.',
    ),
  );

  void _validateFeature(ControlFeature feature, String value) {
    final valid = feature == ControlFeature.platformProfile
        ? const {
            'quiet',
            'low-power',
            'power-saver',
            'balanced',
            'performance',
            'balanced-performance',
            'custom',
            'max-power',
          }.contains(value)
        : {
            ControlFeature.overdrive,
            ControlFeature.winKey,
            ControlFeature.cpuOverclock,
            ControlFeature.gpuOverclock,
            ControlFeature.yLogoLight,
            ControlFeature.ioPortLight,
          }.contains(feature)
        ? value == '0' || value == '1'
        : _integerRanges[feature]?.contains(int.tryParse(value), value) ??
              false;
    if (!valid) _unsupported('Unsupported or malformed feature value.');
  }

  static const _integerRanges = <ControlFeature, _IntRange>{
    ControlFeature.cpuLongtermPowerLimit: _IntRange(5, 200),
    ControlFeature.cpuShorttermPowerLimit: _IntRange(5, 200),
    ControlFeature.cpuPeakPowerLimit: _IntRange(1, 200),
    ControlFeature.cpuCrossLoadingPowerLimit: _IntRange(1, 100),
    ControlFeature.cpuApuSpptPowerLimit: _IntRange(1, 100),
    ControlFeature.gpuCtgpPowerLimit: _IntRange(1, 200),
    ControlFeature.gpuPpabPowerLimit: _IntRange(1, 200),
    ControlFeature.gpuBoostClock: _IntRange(1, 10000),
    ControlFeature.gpuTemperatureLimit: _IntRange(1, 120),
  };

  void _validateBytes(List<int> bytes, int max, String label) {
    if (bytes.isEmpty ||
        bytes.length > max ||
        bytes.any((byte) => byte < 0 || byte > 255)) {
      _unsupported('Invalid $label payload.');
    }
  }

  Never _unsupported(String message) =>
      throw LegionControlNotSupportedException(message);

  LegionControlException _translateDbusError(
    DBusMethodResponseException error,
  ) {
    final name = error.errorName;
    final message = error.toString();
    if (name.endsWith('AccessDenied') || name.endsWith('AuthFailed')) {
      return LegionControlPermissionDeniedException(message);
    }
    if (name.endsWith('ServiceUnknown') ||
        name.endsWith('UnknownObject') ||
        name.endsWith('UnknownInterface') ||
        name.endsWith('UnknownMethod')) {
      return _setupError(message);
    }
    if (name.endsWith('Error.Authorization')) {
      return _setupError(message);
    }
    if (name.endsWith('InvalidArgs') || name.endsWith('NotSupported')) {
      return LegionControlNotSupportedException(message);
    }
    if (name.endsWith('Error.Unavailable')) {
      return LegionControlUnavailableException(message);
    }
    if (name.endsWith('Error.GraphicsBlocked')) {
      return LegionControlGraphicsBlockedException(message);
    }
    if (name.endsWith('Error.GraphicsPending')) {
      return LegionControlGraphicsPendingException(message);
    }
    if (name.endsWith('Busy')) return LegionControlBusyException(message);
    if (name.endsWith('Timeout') || name.endsWith('TimedOut')) {
      return LegionControlTimeoutException(message);
    }
    return LegionControlCommandFailedException(message);
  }

  bool _isAuthorizationFailure(DBusMethodResponseException error) {
    final name = error.errorName;
    return name.endsWith('AccessDenied') || name.endsWith('AuthFailed');
  }
}

class _IntRange {
  const _IntRange(this.min, this.max);
  final int min;
  final int max;
  bool contains(int? value, String raw) =>
      value != null &&
      RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(raw) &&
      value >= min &&
      value <= max;
}
