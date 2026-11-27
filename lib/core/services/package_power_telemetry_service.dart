import 'dart:async';

import 'package:flutter/services.dart';

import 'control_launcher.dart';
import 'legion_control_client.dart';
import 'native_control_connection.dart';

abstract interface class PackagePowerTelemetryClient {
  Future<void> enable();
  Future<void> disable();
  Future<double?> readPackagePowerWatts();
}

/// Owns the read-only CPU power helper for the current app session.
class SessionPackagePowerClient implements PackagePowerTelemetryClient {
  SessionPackagePowerClient({ControlLauncher Function()? createLauncher})
    : _createLauncher =
          createLauncher ??
          (() => ControlLauncher(session: HelperSession.packagePower));

  final ControlLauncher Function() _createLauncher;
  ControlLauncher? _launcher;
  NativeControlConnection? _peer;
  Future<void>? _starting;
  Future<void>? _stopping;
  bool _ready = false;
  bool _closed = false;

  @override
  Future<void> enable() async {
    _ensureOpen();
    await (_starting ??= _start());
  }

  Future<void> _start() async {
    try {
      final launcher = _launcher = _createLauncher();
      final endpoint = await launcher.start();
      _ensureOpen();
      final peer = _peer = NativeControlConnection(
        endpoint: endpoint,
        channel: const MethodChannel('io.github.prnice.legion/package_power'),
      );
      await peer.prepare();
      _ensureOpen();
      _ready = true;
    } on LegionControlStartupDeniedException {
      await disable();
      rethrow;
    } catch (_) {
      await close();
      rethrow;
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw const LegionControlUnavailableException(
        'The CPU power connection is closed. Reopen the app to try again.',
      );
    }
  }

  @override
  Future<double?> readPackagePowerWatts() async {
    if (!_ready) return null;
    try {
      final peer = _peer;
      final watts = await peer?.readPackagePower();
      return _ready && identical(_peer, peer) ? watts : null;
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> disable() {
    _ready = false;
    return _stopping ??= _stop();
  }

  Future<void> _stop() async {
    try {
      await Future.wait([
        if (_peer case final peer?)
          peer.close().timeout(const Duration(seconds: 5)),
        if (_launcher case final launcher?) launcher.close(),
      ]);
    } catch (_) {
      _closed = true;
      rethrow;
    }
    _peer = null;
    _launcher = null;
    _starting = null;
    _stopping = null;
  }

  Future<void> close() {
    _closed = true;
    return disable();
  }
}
