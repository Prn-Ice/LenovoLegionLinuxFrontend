import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/platform_surfaces/models/platform_event.dart';
import 'package:legion_frontend/features/platform_surfaces/notifications/desktop_notifications.dart';

class FakeBus extends Fake implements DBusClient {
  String? owner = ':1.42';
  Object? failure;
  Completer<String?>? pendingOwner;
  Completer<DBusMethodSuccessResponse>? pendingNotify;
  final notifyStarted = Completer<void>();
  final calls = <List<DBusValue>>[];
  int closes = 0;

  @override
  Future<String?> getNameOwner(String name) async {
    expect(name, 'org.freedesktop.Notifications');
    return pendingOwner == null ? owner : pendingOwner!.future;
  }

  @override
  Future<DBusMethodSuccessResponse> callMethod({
    String? destination,
    required DBusObjectPath path,
    String? interface,
    required String name,
    Iterable<DBusValue> values = const [],
    DBusSignature? replySignature,
    bool noReplyExpected = false,
    bool noAutoStart = false,
    bool allowInteractiveAuthorization = false,
  }) async {
    expect(destination, owner);
    expect(path.value, '/org/freedesktop/Notifications');
    expect(interface, 'org.freedesktop.Notifications');
    expect(name, 'Notify');
    expect(replySignature, DBusSignature('u'));
    expect(noAutoStart, isTrue);
    expect(allowInteractiveAuthorization, isFalse);
    calls.add(values.toList());
    if (!notifyStarted.isCompleted) notifyStarted.complete();
    if (failure != null) throw failure!;
    if (pendingNotify != null) return pendingNotify!.future;
    return DBusMethodSuccessResponse([const DBusUint32(17)]);
  }

  @override
  Future<void> close() async => closes++;
}

void main() {
  const event = PowerModeChanged(label: 'Quiet');

  test(
    'default opt-out, visible results and invalid events never connect',
    () async {
      final notifications = DesktopNotifications(
        createClient: () => throw StateError('must not connect'),
      );
      expect(await notifications.show(event), NotificationDelivery.suppressed);
      expect(
        await notifications.show(event, enabled: true),
        NotificationDelivery.suppressed,
      );
      expect(
        await notifications.show(
          const KeyboardBrightnessChanged(fraction: double.nan),
          enabled: true,
          resultVisible: false,
        ),
        NotificationDelivery.suppressed,
      );
      await notifications.close();
    },
  );

  test(
    'real Notify signature, escaped body, no actions and per-kind replacement',
    () async {
      final bus = FakeBus();
      final notifications = DesktopNotifications(createClient: () => bus);
      addTearDown(notifications.close);
      expect(
        await notifications.show(
          const PowerModeChanged(label: '<b>A&B</b>'),
          enabled: true,
          resultVisible: false,
        ),
        NotificationDelivery.sent,
      );
      await notifications.show(event, enabled: true, resultVisible: false);
      await notifications.show(
        const FanBoostChanged(enabled: true),
        enabled: true,
        resultVisible: false,
      );
      expect(
        bus.calls.first[4],
        const DBusString('Power mode: &lt;b&gt;A&amp;B&lt;/b&gt;'),
      );
      expect(bus.calls.first[5], DBusArray.string([]));
      expect(bus.calls.first[6], DBusDict.stringVariant({}));
      expect(bus.calls.first[7], const DBusInt32(4000));
      expect(bus.calls.map((call) => call[1]), [
        const DBusUint32(0),
        const DBusUint32(17),
        const DBusUint32(0),
      ]);
    },
  );

  test('absent server is nonfatal and later appearance retries', () async {
    final bus = FakeBus()..owner = null;
    final notifications = DesktopNotifications(createClient: () => bus);
    addTearDown(notifications.close);
    expect(
      await notifications.show(event, enabled: true, resultVisible: false),
      NotificationDelivery.unavailable,
    );
    expect(bus.calls, isEmpty);
    bus.owner = ':1.42';
    expect(
      await notifications.show(event, enabled: true, resultVisible: false),
      NotificationDelivery.sent,
    );
  });

  test('server replacement resets notification IDs', () async {
    final bus = FakeBus();
    final notifications = DesktopNotifications(createClient: () => bus);
    addTearDown(notifications.close);
    await notifications.show(event, enabled: true, resultVisible: false);
    bus.owner = ':1.99';
    await notifications.show(event, enabled: true, resultVisible: false);
    expect(bus.calls.last[1], const DBusUint32(0));
  });

  test('failed bus is closed and next event uses a new connection', () async {
    final failed = FakeBus()..failure = StateError('disconnected');
    final recovered = FakeBus();
    var creations = 0;
    final notifications = DesktopNotifications(
      createClient: () => creations++ == 0 ? failed : recovered,
    );
    expect(
      await notifications.show(event, enabled: true, resultVisible: false),
      NotificationDelivery.unavailable,
    );
    expect(failed.closes, 1);
    expect(
      await notifications.show(event, enabled: true, resultVisible: false),
      NotificationDelivery.sent,
    );
    await notifications.close();
    await notifications.close();
    expect(recovered.closes, 1);
    expect(failed.closes, 1);
  });

  test('close during lookup suppresses Notify and queued work', () async {
    final owner = Completer<String?>();
    final bus = FakeBus()..pendingOwner = owner;
    final notifications = DesktopNotifications(createClient: () => bus);
    final first = notifications.show(
      event,
      enabled: true,
      resultVisible: false,
    );
    await Future<void>.value();
    final second = notifications.show(
      event,
      enabled: true,
      resultVisible: false,
    );
    final closing = notifications.close();
    expect(await first, NotificationDelivery.disposed);
    expect(await second, NotificationDelivery.disposed);
    await closing;
    expect(owner.isCompleted, isFalse);
    expect(bus.calls, isEmpty);
    expect(bus.closes, 1);
    expect(await notifications.show(event), NotificationDelivery.disposed);
  });

  test(
    'close releases a hung Notify without a reply or double close',
    () async {
      final reply = Completer<DBusMethodSuccessResponse>();
      final bus = FakeBus()..pendingNotify = reply;
      final notifications = DesktopNotifications(createClient: () => bus);
      final delivery = notifications.show(
        event,
        enabled: true,
        resultVisible: false,
      );
      await bus.notifyStarted.future;
      await notifications.close();
      expect(await delivery, NotificationDelivery.disposed);
      expect(reply.isCompleted, isFalse);
      expect(bus.closes, 1);
      reply.completeError(StateError('socket closed'));
      await Future<void>.value();
      await notifications.close();
      expect(bus.closes, 1);
    },
  );
}
