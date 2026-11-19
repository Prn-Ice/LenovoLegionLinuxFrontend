import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../control/dart/peer_server.dart';

void main() {
  late Directory temporary;
  late ControlPeerServer server;
  late String socket;
  late String library;
  late int uid;
  late bool alive;
  late Completer<void> disconnected;
  final clients = <DBusClient>[];
  final calls = <String>[];

  setUpAll(() async {
    final result = await Process.run('pkg-config', [
      '--variable=libdir',
      'libsystemd',
    ]);
    library = result.exitCode == 0
        ? '${(result.stdout as String).trim()}/libsystemd.so.0'
        : 'libsystemd.so.0';
    final identity = File('/proc/self/status')
        .readAsLinesSync()
        .firstWhere((line) => line.startsWith('Uid:'));
    uid = int.parse(identity.split(RegExp(r'\s+'))[1]);
  });

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('control-peer-');
    socket = '${temporary.path}/control.sock';
    alive = true;
    disconnected = Completer<void>();
    calls.clear();
  });

  void start({int? expectedPid}) {
    server = ControlPeerServer(
      path: socket,
      libraryPath: library,
      appPid: expectedPid ?? pid,
      appUid: uid,
      sessionAlive: () => alive,
      onDisconnect: () {
        if (!disconnected.isCompleted) disconnected.complete();
      },
      onCall: (method, arguments) async {
        calls.add(method);
        if (method == 'GetCapabilities') {
          return const PeerReply([
            1,
            ['interactive-control'],
          ]);
        }
        if (method == 'SetFeature') {
          return const PeerReply.error(
            '$controlInterface.Error.Busy',
            'another operation is running',
          );
        }
        if (method == 'ApplyFanCurve') {
          expect(arguments.single, Uint8List.fromList([1, 2, 3]));
        }
        return const PeerReply();
      },
    );
    server.start();
  }

  DBusRemoteObject connect() {
    final client = DBusClient(
      DBusAddress('unix:path=$socket'),
      messageBus: false,
    );
    clients.add(client);
    return DBusRemoteObject(
      client,
      name: controlInterface,
      path: DBusObjectPath(controlObjectPath),
    );
  }

  tearDown(() async {
    server.close();
    for (final client in clients) {
      await client.close();
    }
    clients.clear();
    temporary.deleteSync(recursive: true);
  });

  test(
    'authenticates the pinned process and preserves D-Bus types and errors',
    () async {
      start();
      final remote = connect();
      final reply = await remote.callMethod(
        controlInterface,
        'GetCapabilities',
        [],
        replySignature: DBusSignature('uas'),
      );
      expect(reply.values, [
        const DBusUint32(1),
        DBusArray.string(['interactive-control']),
      ]);
      await remote.callMethod(controlInterface, 'Authorize', []);
      await remote.callMethod(controlInterface, 'ApplyFanCurve', [
        DBusArray.byte([1, 2, 3]),
      ]);
      await expectLater(
        remote.callMethod(controlInterface, 'SetFeature', [
          const DBusString('OverdriveFeature'),
          const DBusString('1'),
        ]),
        throwsA(
          isA<DBusMethodResponseException>().having(
            (error) => error.response.errorName,
            'error name',
            '$controlInterface.Error.Busy',
          ),
        ),
      );
      expect(calls, [
        'GetCapabilities',
        'Authorize',
        'ApplyFanCurve',
        'SetFeature',
      ]);
    },
  );

  test('rejects wrong signatures before calling the dispatcher', () async {
    start();
    final remote = connect();
    await expectLater(
      remote.callMethod(controlInterface, 'SetToggle', [
        const DBusString('touchpad'),
      ]),
      throwsA(
        isA<DBusMethodResponseException>().having(
          (error) => error.response.errorName,
          'error name',
          'org.freedesktop.DBus.Error.InvalidArgs',
        ),
      ),
    );
    expect(calls, isEmpty);
  });

  test(
    'rejects another PID before the EXTERNAL authentication exchange',
    () async {
      start(expectedPid: pid + 1);
      final client = await Socket.connect(
        InternetAddress(socket, type: InternetAddressType.unix),
        0,
      );
      addTearDown(client.destroy);
      final received = await client
          .fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk))
          .timeout(const Duration(seconds: 3));
      expect(received, isEmpty);
      expect(calls, isEmpty);
      expect(disconnected.isCompleted, isFalse);
    },
  );

  test('reports an authenticated app disconnect', () async {
    start();
    await connect().callMethod(controlInterface, 'Authorize', []);
    await clients.single.close();
    clients.clear();
    await disconnected.future.timeout(const Duration(seconds: 3));
  });
}
