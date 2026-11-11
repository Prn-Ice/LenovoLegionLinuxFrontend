import 'dart:async';
import 'dart:math';

import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';

import '../models/control_capabilities.dart';
import '../models/portable_control_endpoint.dart';
import 'legion_control_client.dart';

export '../models/portable_control_endpoint.dart';

/// A private control connection owned by the Linux host in this app process.
/// The caller must first obtain an endpoint from an explicitly approved launch.
class NativePortableControlTransport extends LegionControlTransport {
  NativePortableControlTransport({
    required PortableControlEndpoint endpoint,
    MethodChannel? channel,
  }) : _endpoint = endpoint,
       _channel =
           channel ??
           const MethodChannel('io.github.prnice.legion/portable_control');

  final PortableControlEndpoint _endpoint;
  final MethodChannel _channel;
  final String _session = _sessionId();
  Future<void>? _connecting;
  Future<void>? _closing;
  bool _closed = false;

  static String _sessionId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  void _ensureOpen() {
    if (_closed) {
      throw const LegionControlUnavailableException(
        'Portable control connection is closed. Restart the app to reconnect.',
      );
    }
  }

  Never _platformFailure(PlatformException error) {
    _ensureOpen();
    final message = error.message ?? 'Portable control connection failed.';
    if (error.code.startsWith('org.freedesktop.DBus.Error.') ||
        error.code.startsWith('io.github.prnice.LegionControl1.Error.')) {
      throw DBusMethodResponseException(
        DBusMethodErrorResponse(error.code, [DBusString(message)]),
      );
    }
    throw switch (error.code) {
      'invalid-arguments' => LegionControlNotSupportedException(message),
      'busy' => LegionControlBusyException(message),
      'timeout' => LegionControlTimeoutException(message),
      'setup' => LegionControlSetupException(message),
      _ => LegionControlUnavailableException(message),
    };
  }

  Future<T?> _native<T>(
    String method, [
    Map<String, Object> arguments = const {},
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, {
        'session': _session,
        ...arguments,
      });
    } on MissingPluginException {
      throw const LegionControlSetupException(
        'Portable control support is unavailable in this app build. Update the app and retry.',
      );
    } on PlatformException catch (error) {
      _platformFailure(error);
    }
  }

  Future<void> _connect() async {
    await _native<void>('connect', {
      'address': _endpoint.address,
      'unit': _endpoint.unit,
      'helperPid': _endpoint.helperPid,
    });
    _ensureOpen();
  }

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object> arguments = const {},
  ]) async {
    await prepare();
    final result = await _native<T>(method, arguments);
    _ensureOpen();
    return result;
  }

  @override
  Future<void> prepare() async {
    _ensureOpen();
    await (_connecting ??= _connect());
    _ensureOpen();
  }

  @override
  Future<ControlCapabilities> getCapabilities() async {
    final reply = await _invoke<Object>('getCapabilities');
    if (reply is! Map ||
        reply['protocolVersion'] is! int ||
        reply['capabilities'] is! List ||
        !(reply['capabilities'] as List).every((value) => value is String)) {
      throw const LegionControlSetupException(
        'The portable helper returned invalid compatibility information. Update the app and retry.',
      );
    }
    final advertised = (reply['capabilities'] as List).cast<String>().toSet();
    return ControlCapabilities(
      protocolVersion: reply['protocolVersion'] as int,
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
  Future<void> authorize() => _invoke<void>('authorize');

  Object _encodeArgument(Object value) {
    if (value is! List<int>) return value;
    if (value.any((byte) => byte < 0 || byte > 255)) {
      throw const LegionControlNotSupportedException(
        'Invalid control payload bytes.',
      );
    }
    return Uint8List.fromList(value);
  }

  @override
  Future<void> call(String method, List<Object> arguments) =>
      _invoke<void>('call', {
        'method': method,
        'arguments': [for (final value in arguments) _encodeArgument(value)],
      });

  @override
  Future<void> close() {
    _closed = true;
    return _closing ??= _connecting == null
        ? Future<void>.value()
        : _closeNative();
  }

  Future<void> _closeNative() async {
    try {
      await _native<void>('close');
    } on LegionControlSetupException {
      // A build without this channel could not have opened a native session.
    }
  }
}
