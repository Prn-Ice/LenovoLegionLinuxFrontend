import 'dart:async';

import 'package:dbus/dbus.dart';

import '../models/control_selectors.dart';
import '../../features/dgpu/models/graphics_mode.dart';

abstract class LegionControlTransport {
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
class DBusLegionControlTransport implements LegionControlTransport {
  DBusLegionControlTransport({DBusClient? client})
    : _client = client ?? DBusClient.system();

  final DBusClient _client;
  bool _closed = false;

  @override
  Future<void> authorize() {
    if (_closed) {
      return Future<void>.error(
        const LegionControlUnavailableException(
          'Control service connection is closed.',
        ),
      );
    }
    return _client
        .callMethod(
          destination: 'io.github.prnice.LegionControl1',
          path: DBusObjectPath('/io/github/prnice/LegionControl1'),
          interface: 'io.github.prnice.LegionControl1',
          name: 'Authorize',
          allowInteractiveAuthorization: true,
          replySignature: DBusSignature.empty,
        )
        .then((_) {});
  }

  @override
  Future<void> call(String method, List<Object> arguments) async {
    if (_closed) {
      throw const LegionControlUnavailableException(
        'Control service connection is closed.',
      );
    }
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
    await _client.callMethod(
      destination: 'io.github.prnice.LegionControl1',
      path: DBusObjectPath('/io/github/prnice/LegionControl1'),
      interface: 'io.github.prnice.LegionControl1',
      name: method,
      values: values,
      replySignature: DBusSignature.empty,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _client.close();
  }
}

/// Validates typed control operations against the narrow D-Bus contract.
class LegionControlClient {
  LegionControlClient({required LegionControlTransport transport})
    : _transport = transport;

  final LegionControlTransport _transport;
  Future<void> _call(
    String method,
    List<Object> arguments, {
    bool retryAfterAuthorizationLoss = true,
  }) async {
    final authorization = _authorization ??= _transport.authorize();
    try {
      await authorization;
    } on DBusMethodResponseException catch (error) {
      if (identical(_authorization, authorization)) _authorization = null;
      throw _translateDbusError(error);
    } catch (_) {
      if (identical(_authorization, authorization)) _authorization = null;
      rethrow;
    }
    try {
      await _transport.call(method, arguments);
    } on DBusMethodResponseException catch (error) {
      if (_isAuthorizationFailure(error)) {
        if (identical(_authorization, authorization)) _authorization = null;
        if (retryAfterAuthorizationLoss) {
          return _call(method, arguments, retryAfterAuthorizationLoss: false);
        }
      }
      throw _translateDbusError(error);
    } catch (_) {
      if (identical(_authorization, authorization)) _authorization = null;
      rethrow;
    }
  }

  Future<void>? _authorization;

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
  Future<void> setServiceEnabled(ControlService service, bool enabled) =>
      _call('SetServiceEnabled', [service.wireValue, enabled]);

  Future<void> close() => _transport.close();

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
      return LegionControlSetupException(message);
    }
    if (name.endsWith('Error.Authorization')) {
      return LegionControlSetupException(message);
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
