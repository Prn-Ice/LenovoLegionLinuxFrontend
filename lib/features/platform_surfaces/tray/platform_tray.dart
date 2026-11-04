import 'dart:async';

import 'tray_menu.dart';

/// Registration means a watcher accepted the item, not that an icon is visible.
enum TrayRegistration { unavailable, registered, disposed }

abstract interface class TrayTransport {
  Stream<bool> get watcherChanges;
  Future<void> open();
  Future<bool> watcherPresent();
  Future<void> register();
  Future<void> updateMenu(List<TrayMenuItem> items);
  Future<void> close();
}

class PlatformTray {
  PlatformTray(this._transport);

  final TrayTransport _transport;
  final _changes = StreamController<TrayRegistration>.broadcast();
  StreamSubscription<bool>? _watcher;
  TrayRegistration _state = TrayRegistration.unavailable;
  int _generation = 0;
  bool _started = false;
  bool _disposed = false;
  Future<void>? _opening;

  TrayRegistration get state => _state;
  Stream<TrayRegistration> get changes => _changes.stream;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    try {
      _opening = _transport.open();
      await _opening;
      if (_disposed) return;
      _watcher = _transport.watcherChanges.listen(
        _watcherChanged,
        onError: (Object _) => _watcherChanged(false),
      );
      final generation = _generation;
      final present = await _transport.watcherPresent();
      if (!_disposed && generation == _generation) _watcherChanged(present);
    } catch (_) {
      if (!_disposed) _setState(TrayRegistration.unavailable);
    }
  }

  void _watcherChanged(bool present) {
    if (_disposed) return;
    final generation = ++_generation;
    _setState(TrayRegistration.unavailable);
    if (present) unawaited(_register(generation));
  }

  Future<void> _register(int generation) async {
    try {
      await _transport.register();
      if (!_disposed && generation == _generation) {
        _setState(TrayRegistration.registered);
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _setState(TrayRegistration.unavailable);
      }
    }
  }

  Future<void> updateMenu(List<TrayMenuItem> items) async {
    if (_disposed) throw StateError('Tray is disposed');
    await _transport.updateMenu(items);
  }

  void _setState(TrayRegistration state) {
    if (_disposed || _state == state) return;
    _state = state;
    _changes.add(state);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    try {
      await _opening;
    } catch (_) {
      // Opening can fail while disposal is waiting for it.
    }
    await _watcher?.cancel();
    await _transport.close();
    _state = TrayRegistration.disposed;
    await _changes.close();
  }
}
