import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

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

typedef BytesReader = Future<List<int>> Function(String path);

/// Maps the legacy legion_cli command vocabulary to the narrow D-Bus contract.
class LegionControlClient {
  LegionControlClient({
    required LegionControlTransport transport,
    BytesReader? bytesReader,
  }) : _transport = transport,
       _bytesReader = bytesReader ?? ((path) => File(path).readAsBytes());

  final LegionControlTransport _transport;
  final BytesReader _bytesReader;
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

  static const _features = <String>{
    'PlatformProfileFeature',
    'OverdriveFeature',
    'WinkeyFeature',
    'CPULongtermPowerLimit',
    'CPUShorttermPowerLimit',
    'CPUPeakPowerLimit',
    'CPUCrossLoadingPowerLimit',
    'CPUAPUSPPTPowerLimit',
    'CPUDefaultPowerLimit',
    'GPUCTGPPowerLimit',
    'GPUPPABPowerLimit',
    'GPUBoostClock',
    'GPUTemperatureLimit',
    'CPUOverclock',
    'GPUOverclock',
    'YLogoLight',
    'IOPortLight',
  };
  static const _booleanFeatures = {
    'OverdriveFeature',
    'WinkeyFeature',
    'CPUOverclock',
    'GPUOverclock',
    'YLogoLight',
    'IOPortLight',
  };
  static const _presets = {
    'quiet-battery',
    'balanced-battery',
    'performance-battery',
    'balanced-performance-battery',
    'quiet-ac',
    'balanced-ac',
    'performance-ac',
    'balanced-performance-ac',
  };
  static const _serviceIds = {'power_profiles_daemon', 'legiond_stack'};

  Future<void> setFeature(String feature, String value) {
    _validateFeature(feature, value);
    return _call('SetFeature', [feature, value]);
  }

  Future<void> setToggle(String id, bool enabled) {
    if (!_toggleIds.contains(id)) _unsupported('Unsupported toggle.');
    return _call('SetToggle', [id, enabled]);
  }

  Future<void> applyFanPreset(String preset) {
    if (!_presets.contains(preset)) _unsupported('Unsupported fan preset.');
    return _call('ApplyFanPreset', [preset]);
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
  Future<void> setServiceEnabled(String id, bool enabled) =>
      _serviceIds.contains(id)
      ? _call('SetServiceEnabled', [id, enabled])
      : _unsupported('Unsupported service.');

  Future<void> runCommand(List<String> args) async {
    if (args.length == 3 && args[0] == 'set-feature') {
      return setFeature(args[1], args[2]);
    }

    final toggle = _toggleCommand(args);
    if (toggle != null) return setToggle(toggle.$1, toggle.$2);
    if (args.length == 2 &&
        args[0] == 'fancurve-write-preset-to-hw' &&
        args[1].isNotEmpty) {
      return applyFanPreset(args[1]);
    }
    if (args.length == 1 && args[0] == 'fancurve-write-current-preset-to-hw') {
      return applyCurrentFanPreset();
    }
    if (args.length == 3 && args[0] == 'custom-conservation-mode-apply') {
      final lower = int.tryParse(args[1]);
      final upper = int.tryParse(args[2]);
      if (lower == null || upper == null) {
        _unsupported('Malformed conservation limits.');
      }
      return applyCustomConservation(lower, upper);
    }
    if (args.length == 2 &&
        args[0] == 'fancurve-write-file-to-hw' &&
        _isPath(args[1])) {
      return applyFanCurve(await _bytesReader(args[1]));
    }
    if (args.length == 3 &&
        args[0] == 'boot-logo' &&
        args[1] == 'enable' &&
        _isPath(args[2])) {
      return setBootLogo(await _bytesReader(args[2]));
    }
    if (args.length == 2 && args[0] == 'boot-logo' && args[1] == 'restore') {
      return restoreBootLogo();
    }
    throw const LegionControlNotSupportedException(
      'Unsupported privileged command.',
    );
  }

  Future<void> close() => _transport.close();

  static const _toggleIds = {
    'hybrid-mode',
    'battery-conservation',
    'rapid-charging',
    'always-on-usb-charging',
    'touchpad',
    'fn-lock',
    'mini-fan-curve',
    'lock-fan-controller',
    'maximum-fan-speed',
  };

  void _validateFeature(String feature, String value) {
    if (!_features.contains(feature)) _unsupported('Unsupported feature.');
    final valid = feature == 'PlatformProfileFeature'
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
        : _booleanFeatures.contains(feature)
        ? value == '0' || value == '1'
        : _integerRanges[feature]?.contains(int.tryParse(value), value) ??
              false;
    if (!valid) _unsupported('Unsupported or malformed feature value.');
  }

  static const _integerRanges = <String, _IntRange>{
    'CPULongtermPowerLimit': _IntRange(5, 200),
    'CPUShorttermPowerLimit': _IntRange(5, 200),
    'CPUPeakPowerLimit': _IntRange(1, 200),
    'CPUCrossLoadingPowerLimit': _IntRange(1, 100),
    'CPUAPUSPPTPowerLimit': _IntRange(1, 100),
    'CPUDefaultPowerLimit': _IntRange(1, 100),
    'GPUCTGPPowerLimit': _IntRange(1, 200),
    'GPUPPABPowerLimit': _IntRange(1, 200),
    'GPUBoostClock': _IntRange(1, 10000),
    'GPUTemperatureLimit': _IntRange(1, 120),
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

  (String, bool)? _toggleCommand(List<String> args) {
    if (args.length != 1) return null;
    const commands = {
      'hybrid-mode-enable': ('hybrid-mode', true),
      'hybrid-mode-disable': ('hybrid-mode', false),
      'batteryconservation-enable': ('battery-conservation', true),
      'batteryconservation-disable': ('battery-conservation', false),
      'rapid-charging-enable': ('rapid-charging', true),
      'rapid-charging-disable': ('rapid-charging', false),
      'minifancurve-enable': ('mini-fan-curve', true),
      'minifancurve-disable': ('mini-fan-curve', false),
      'lockfancontroller-enable': ('lock-fan-controller', true),
      'lockfancontroller-disable': ('lock-fan-controller', false),
      'maximumfanspeed-enable': ('maximum-fan-speed', true),
      'maximumfanspeed-disable': ('maximum-fan-speed', false),
      'always-on-usb-charging-enable': ('always-on-usb-charging', true),
      'always-on-usb-charging-disable': ('always-on-usb-charging', false),
      'touchpad-enable': ('touchpad', true),
      'touchpad-disable': ('touchpad', false),
      'fnlock-enable': ('fn-lock', true),
      'fnlock-disable': ('fn-lock', false),
    };
    return commands[args[0]];
  }

  bool _isPath(String path) =>
      path.isNotEmpty && path.startsWith('/') && !path.contains('\u0000');
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
