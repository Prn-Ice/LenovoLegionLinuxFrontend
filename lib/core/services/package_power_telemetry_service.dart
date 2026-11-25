import 'dart:async';

import 'package:flutter/services.dart';

import 'native_control_connection.dart';
import 'control_launcher.dart';

abstract interface class PackagePowerTelemetryClient {
  Future<void> enable();
  Future<double?> readPackagePowerWatts();
}

/// Starts a read-only session after the user chooses Allow. Polling sensors
/// never starts a helper or prompts for permission.
class SessionPackagePowerClient implements PackagePowerTelemetryClient {
  SessionPackagePowerClient({ControlLauncher? launcher})
    : _launcher =
          launcher ?? ControlLauncher(session: HelperSession.packagePower);

  final ControlLauncher _launcher;
  NativeControlConnection? _peer;
  bool _closed = false;

  @override
  Future<void> enable() async {
    try {
      final endpoint = await _launcher.start();
      if (_closed) return;
      final peer = _peer = NativeControlConnection(
        endpoint: endpoint,
        channel: const MethodChannel('io.github.prnice.legion/package_power'),
      );
      await peer.prepare();
    } catch (_) {
      await close();
      rethrow;
    }
  }

  @override
  Future<double?> readPackagePowerWatts() async {
    try {
      return await _peer?.readPackagePower();
    } on Exception {
      return null;
    }
  }

  Future<void> close() async {
    _closed = true;
    final peer = _peer;
    _peer = null;
    await Future.wait([if (peer != null) peer.close(), _launcher.close()]);
  }
}
