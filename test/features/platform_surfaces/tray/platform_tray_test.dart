import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/platform_surfaces/tray/dbus_tray_transport.dart';
import 'package:legion_frontend/features/platform_surfaces/tray/platform_tray.dart';
import 'package:legion_frontend/features/platform_surfaces/tray/tray_menu.dart';

class FakeTransport implements TrayTransport {
  final events = StreamController<bool>.broadcast(sync: true);
  final registrations = <Completer<void>>[];
  final opened = Completer<void>();
  bool present = false;
  bool closed = false;
  @override
  Stream<bool> get watcherChanges => events.stream;
  @override
  Future<void> open() => opened.future;
  @override
  Future<bool> watcherPresent() async => present;
  @override
  Future<void> register() {
    final result = Completer<void>();
    registrations.add(result);
    return result.future;
  }

  @override
  Future<void> updateMenu(List<TrayMenuItem> items) async {}
  @override
  Future<void> close() async {
    closed = true;
    await events.close();
  }
}

class FakeWatcher extends DBusObject {
  FakeWatcher() : super(DBusObjectPath('/StatusNotifierWatcher'));
  final registration = Completer<DBusMethodCall>();

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == 'org.kde.StatusNotifierWatcher' &&
        call.name == 'RegisterStatusNotifierItem' &&
        call.signature == DBusSignature('s')) {
      registration.complete(call);
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}

void main() {
  test(
    'watcher replacement ignores stale registration and disposal closes',
    () async {
      final transport = FakeTransport();
      final tray = PlatformTray(transport);
      transport.opened.complete();
      await tray.start();
      transport.events.add(true);
      transport.events.add(false);
      transport.events.add(true);
      transport.registrations.first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(tray.state, TrayRegistration.unavailable);
      transport.registrations.last.complete();
      await Future<void>.delayed(Duration.zero);
      expect(tray.state, TrayRegistration.registered);
      await tray.dispose();
      expect(transport.closed, isTrue);
      expect(tray.state, TrayRegistration.disposed);
    },
  );

  test('dispose waits for opening and never registers afterwards', () async {
    final transport = FakeTransport()..present = true;
    final tray = PlatformTray(transport);
    final starting = tray.start();
    final disposing = tray.dispose();
    expect(transport.closed, isFalse);
    transport.opened.complete();
    await starting;
    await disposing;
    expect(transport.registrations, isEmpty);
    expect(transport.closed, isTrue);
  });

  test('registers the exported object with an existing watcher', () async {
    final server = DBusServer();
    final address = await server.listenAddress(
      DBusAddress.unix(dir: Directory('/tmp/opencode')),
    );
    final watcherClient = DBusClient(address);
    final watcher = FakeWatcher();
    await watcherClient.registerObject(watcher);
    await watcherClient.requestName('org.kde.StatusNotifierWatcher');
    final client = DBusClient(address);
    final tray = PlatformTray(DBusTrayTransport(client: client));
    addTearDown(() async {
      await tray.dispose();
      await watcherClient.close();
      await server.close();
    });
    final registered = tray.changes.firstWhere(
      (state) => state == TrayRegistration.registered,
    );
    await tray.start();
    final call = await watcher.registration.future;
    await registered;
    expect(call.sender, client.uniqueName);
    expect(call.values.single.asString(), '/StatusNotifierItem');
  });

  test('exported menu has native layout and ignores disabled clicks', () async {
    final server = DBusServer();
    final address = await server.listenAddress(
      DBusAddress.unix(dir: Directory('/tmp/opencode')),
    );
    final client = DBusClient(address);
    final peer = DBusClient(address);
    final transport = DBusTrayTransport(client: client);
    addTearDown(() async {
      await transport.close();
      await peer.close();
      await server.close();
    });
    await transport.open();
    var calls = 0;
    await transport.updateMenu([
      TrayMenuItem(id: 1, label: 'Unavailable', onActivate: () => calls++),
      TrayMenuItem(
        id: 2,
        label: 'Mode',
        enabled: true,
        toggleType: 'radio',
        checked: true,
        onActivate: () => calls++,
      ),
    ]);
    final item = DBusRemoteObject(
      peer,
      name: client.uniqueName,
      path: DBusObjectPath('/StatusNotifierItem'),
    );
    expect(
      (await item.getProperty(
        'org.kde.StatusNotifierItem',
        'Menu',
      )).asObjectPath(),
      DBusObjectPath('/MenuBar'),
    );
    final menu = DBusRemoteObject(
      peer,
      name: client.uniqueName,
      path: DBusObjectPath('/MenuBar'),
    );
    final layout = await menu.callMethod(
      'com.canonical.dbusmenu',
      'GetLayout',
      [DBusInt32(0), DBusInt32(-1), DBusArray.string([])],
    );
    expect(layout.signature, DBusSignature('u(ia{sv}av)'));
    for (final id in [1, 2]) {
      await menu.callMethod('com.canonical.dbusmenu', 'Event', [
        DBusInt32(id),
        DBusString('clicked'),
        DBusVariant(DBusInt32(0)),
        DBusUint32(0),
      ]);
    }
    expect(calls, 1);
  });
}
