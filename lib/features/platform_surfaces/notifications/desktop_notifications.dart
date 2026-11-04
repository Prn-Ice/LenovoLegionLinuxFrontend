import 'dart:async';

import 'package:dbus/dbus.dart';

import '../models/platform_event.dart';

enum NotificationDelivery { sent, suppressed, unavailable, disposed }

/// Optional desktop feedback. Construction does not connect to the session bus.
/// The owner must close this service; injected clients are owned too.
class DesktopNotifications {
  DesktopNotifications({DBusClient Function()? createClient})
    : _createClient = createClient ?? DBusClient.session;

  final DBusClient Function() _createClient;
  DBusClient? _client;
  String? _serverOwner;
  final Map<Type, int> _replacementIds = {};
  Future<void> _pending = Future.value();
  Future<void>? _closing;
  final Completer<void> _disposeSignal = Completer<void>();
  bool _disposed = false;

  /// Call only with confirmed changes. Re-evaluate preferences and visibility
  /// at the integration boundary; initial snapshots must not be sent as changes.
  Future<NotificationDelivery> show(
    PlatformEvent event, {
    bool enabled = false,
    bool resultVisible = true,
  }) {
    if (_disposed) return Future.value(NotificationDelivery.disposed);
    final body = _body(event);
    if (!enabled || resultVisible || body == null) {
      return Future.value(NotificationDelivery.suppressed);
    }
    final result = _pending.then((_) => _send(event.runtimeType, body));
    _pending = result.then((_) {});
    return result;
  }

  Future<NotificationDelivery> _send(Type kind, String body) async {
    if (_disposed) return NotificationDelivery.disposed;
    try {
      final client = _client ??= _createClient();
      // Resolve every time: IDs belong to one notification server, not the bus.
      final owner = await _untilDisposed(
        client.getNameOwner('org.freedesktop.Notifications'),
      );
      if (_disposed) return NotificationDelivery.disposed;
      if (owner != _serverOwner) {
        _serverOwner = owner;
        _replacementIds.clear();
      }
      if (owner == null) return NotificationDelivery.unavailable;
      final response = await _untilDisposed(
        client.callMethod(
          destination: owner,
          path: DBusObjectPath('/org/freedesktop/Notifications'),
          interface: 'org.freedesktop.Notifications',
          name: 'Notify',
          values: [
            const DBusString('Legion'),
            DBusUint32(_replacementIds[kind] ?? 0),
            const DBusString(''),
            const DBusString('Legion'),
            DBusString(_escapeBody(body)),
            DBusArray.string([]),
            DBusDict.stringVariant({}),
            const DBusInt32(4000),
          ],
          replySignature: DBusSignature('u'),
          noAutoStart: true,
        ),
      );
      if (_disposed) return NotificationDelivery.disposed;
      _replacementIds[kind] =
          (response.returnValues.single as DBusUint32).value;
      return NotificationDelivery.sent;
    } catch (_) {
      _replacementIds.clear();
      _serverOwner = null;
      final client = _client;
      _client = null;
      if (client != null) {
        try {
          await client.close();
        } catch (_) {
          // Desktop feedback must not turn a completed hardware action into an error.
        }
      }
      return _disposed
          ? NotificationDelivery.disposed
          : NotificationDelivery.unavailable;
    }
  }

  // dbus 0.8.0 close() does not complete outstanding method completers.
  // Keep their eventual errors observed without waiting for a remote reply.
  Future<T> _untilDisposed<T>(Future<T> operation) => Future.any([
    operation,
    _disposeSignal.future.then<T>((_) => throw StateError('Disposed')),
  ]);

  /// Idempotent. Pending operations cannot start another connection after close.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _disposed = true;
    _disposeSignal.complete();
    final client = _client;
    _client = null;
    _replacementIds.clear();
    try {
      if (client != null) await client.close();
    } finally {
      await _pending;
    }
  }
}

String _escapeBody(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String? _body(PlatformEvent event) => switch (event) {
  PowerModeChanged(:final label)
      when label != null && label.trim().isNotEmpty =>
    'Power mode: $label',
  KeyboardBrightnessChanged(:final fraction)
      when fraction != null &&
          fraction.isFinite &&
          fraction >= 0 &&
          fraction <= 1 =>
    'Keyboard brightness: ${(fraction * 100).round()}%',
  FanBoostChanged(:final enabled) when enabled != null =>
    'Fan boost ${enabled ? 'enabled' : 'disabled'}',
  AutomationChanged(:final description)
      when description != null && description.trim().isNotEmpty =>
    description,
  _ => null,
};
