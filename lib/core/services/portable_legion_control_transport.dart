import 'dart:async';
import 'dart:io';

import '../models/control_capabilities.dart';
import 'legion_control_client.dart';
import 'native_portable_control_transport.dart';
import 'portable_control_launcher.dart';

/// Owns one approved launch and its private connection for the app session.
class PortableLegionControlTransport extends LegionControlTransport {
  PortableLegionControlTransport({
    PortableControlLauncher? launcher,
    LegionControlTransport Function(PortableControlEndpoint)? connect,
  }) : _launcher =
           launcher ??
           PortableControlLauncher(
             executable:
                 '${File(Platform.resolvedExecutable).parent.path}/libexec/legion-portable-control',
           ),
       _connect =
           connect ??
           ((endpoint) => NativePortableControlTransport(endpoint: endpoint)) {
    _launcher.ended.then((error) {
      _failure ??= error;
      unawaited(
        close().catchError((Object _) {
          // The cached close future retains cleanup failures for the owner.
        }),
      );
    });
  }

  final PortableControlLauncher _launcher;
  final LegionControlTransport Function(PortableControlEndpoint) _connect;
  LegionControlTransport? _peer;
  LegionControlException? _failure;
  Future<LegionControlTransport>? _opening;
  Future<void>? _closing;
  bool _closed = false;

  void _ensureOpen() {
    if (_closed) {
      throw _failure ??
          const LegionControlUnavailableException(
            'Portable control is closed. Start a new app session to retry.',
          );
    }
  }

  Future<LegionControlTransport> _open() async {
    try {
      final endpoint = await _launcher.start();
      _ensureOpen();
      return _peer = _connect(endpoint);
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<T> _withPeer<T>(
    Future<T> Function(LegionControlTransport) operation,
  ) async {
    _ensureOpen();
    final peer = await (_opening ??= _open());
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
      _launcher.close(),
    ]);
  }
}
