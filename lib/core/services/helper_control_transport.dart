import 'dart:async';

import '../models/control_capabilities.dart';
import 'legion_control_client.dart';
import 'native_control_connection.dart';
import 'control_launcher.dart';
import 'native_host_cli_resolver.dart';

/// Owns approval attempts and one approved private connection for the app session.
class HelperControlTransport extends LegionControlTransport {
  HelperControlTransport({
    ControlLauncher Function()? createLauncher,
    Future<String> Function()? resolveCliPath,
    LegionControlTransport Function(ControlEndpoint)? connect,
  }) : _resolveCliPath = resolveCliPath ?? resolveNativeHostCli,
       _createLauncher = createLauncher ?? ControlLauncher.new,
       _connect =
           connect ??
           ((endpoint) => NativeControlConnection(endpoint: endpoint));

  final ControlLauncher Function() _createLauncher;
  final Future<String> Function() _resolveCliPath;
  final LegionControlTransport Function(ControlEndpoint) _connect;
  ControlLauncher? _launcher;
  LegionControlTransport? _peer;
  LegionControlException? _failure;
  Future<LegionControlTransport>? _opening;
  Future<void>? _closing;
  bool _closed = false;

  void _ensureOpen() {
    if (_closed) {
      throw _failure ??
          const LegionControlUnavailableException(
            'Hardware control is closed. Start a new app session to retry.',
          );
    }
  }

  Future<LegionControlTransport> _open() async {
    try {
      final expectedCli = await _resolveCliPath();
      _ensureOpen();
      final launcher = _launcher = _createLauncher();
      final endpoint = await launcher.start();
      if (endpoint.cliPath != expectedCli) {
        throw const ControlHelperSetupException(
          'The installed CLI changed after this app session started. Restart the app to select it again before changing hardware settings.',
        );
      }
      _ensureOpen();
      final peer = _peer = _connect(endpoint);
      launcher.ended.then((error) {
        _failure ??= error;
        unawaited(
          close().catchError((Object _) {
            // The cached close future retains cleanup failures for the owner.
          }),
        );
      });
      return peer;
    } on LegionControlStartupDeniedException {
      await _launcher?.close();
      _ensureOpen();
      _launcher = null;
      rethrow;
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<T> _withPeer<T>(
    Future<T> Function(LegionControlTransport) operation,
  ) async {
    _ensureOpen();
    final opening = _opening ??= _open();
    final LegionControlTransport peer;
    try {
      peer = await opening;
    } on LegionControlStartupDeniedException {
      if (identical(_opening, opening)) _opening = null;
      rethrow;
    }
    _ensureOpen();
    final value = await operation(peer);
    _ensureOpen();
    return value;
  }

  @override
  Future<void> prepare() => _withPeer((peer) => peer.prepare());

  @override
  Future<ControlCapabilities> getCapabilities() async {
    try {
      return await _withPeer((peer) => peer.getCapabilities());
    } on LegionControlStartupDeniedException {
      rethrow;
    } catch (_) {
      await close();
      rethrow;
    }
  }

  @override
  Future<void> authorize() => _withPeer((peer) => peer.authorize());

  @override
  Future<void> call(String method, List<Object> arguments) =>
      _withPeer((peer) => peer.call(method, arguments));

  @override
  Future<void> close() {
    _closed = true;
    return _closing ??= _closeOwnedResources();
  }

  Future<void> _closeOwnedResources() async {
    await Future.wait([
      if (_peer case final peer?)
        peer.close().timeout(const Duration(seconds: 5)),
      if (_launcher case final launcher?) launcher.close(),
    ]);
  }
}
