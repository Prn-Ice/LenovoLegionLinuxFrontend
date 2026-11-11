import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/control_capabilities.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/services/native_portable_control_transport.dart';

const endpoint = PortableControlEndpoint(
  address: 'unix:path=/run/legion-example/control.sock',
  unit: 'legion-bootstrap-probe-01234567-89ab-4cde-8fab-0123456789ab.service',
  helperPid: 123,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/portable-control');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Object? metadata;
  Future<Object?> Function(MethodCall)? handler;

  setUp(() {
    calls = [];
    metadata = {
      'protocolVersion': 1,
      'capabilities': ['interactive-control', 'future-capability'],
    };
    handler = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (handler != null) return handler!(call);
      return call.method == 'getCapabilities' ? metadata : null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  NativePortableControlTransport transport() =>
      NativePortableControlTransport(endpoint: endpoint, channel: channel);

  test('negotiates before authorization and sends typed operations', () async {
    final peer = transport();
    final client = LegionControlClient(transport: peer);
    addTearDown(client.close);
    await client.setToggle(ControlToggle.batteryConservation, true);
    await client.applyFanCurve([0, 128, 255]);
    expect(calls.map((call) => call.method), [
      'connect',
      'getCapabilities',
      'authorize',
      'call',
      'call',
    ]);
    final session = calls.first.arguments['session'];
    expect(calls.every((call) => call.arguments['session'] == session), isTrue);
    expect(calls.first.arguments['helperPid'], 123);
    expect(calls[3].arguments['method'], 'SetToggle');
    expect(calls[3].arguments['arguments'], ['battery-conservation', true]);
    expect(calls.last.arguments['arguments'].single, isA<Uint8List>());
    expect(calls.last.arguments['arguments'].single, [0, 128, 255]);
    expect((await client.getCapabilities()).supported, {
      ControlCapability.interactiveControl,
    });
  });

  test(
    'concurrent first calls share connection, metadata and authorization',
    () async {
      final peer = transport();
      final client = LegionControlClient(transport: peer);
      addTearDown(client.close);
      await Future.wait([
        client.setToggle(ControlToggle.batteryConservation, true),
        client.setToggle(ControlToggle.rapidCharging, false),
      ]);
      expect(calls.where((call) => call.method == 'connect'), hasLength(1));
      expect(
        calls.where((call) => call.method == 'getCapabilities'),
        hasLength(1),
      );
      expect(calls.where((call) => call.method == 'authorize'), hasLength(1));
      expect(calls.where((call) => call.method == 'call'), hasLength(2));
    },
  );

  test(
    'close cancels native startup before its reply without waiting for it',
    () async {
      final started = Completer<void>();
      final connection = Completer<void>();
      handler = (call) async {
        if (call.method == 'connect') {
          started.complete();
          await connection.future;
        }
        return null;
      };
      final client = LegionControlClient(transport: transport());
      final rejected = expectLater(
        client.setToggle(ControlToggle.batteryConservation, true),
        throwsA(isA<LegionControlUnavailableException>()),
      );
      await started.future;
      await client.close();
      await rejected;
      connection.complete();
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((call) => call.method), ['connect', 'close']);
      expect(calls.first.arguments['session'], calls.last.arguments['session']);
    },
  );

  test('malformed native metadata stops before authorization', () async {
    for (final response in [
      null,
      {'protocolVersion': '1', 'capabilities': []},
      {
        'protocolVersion': 1,
        'capabilities': [42],
      },
    ]) {
      metadata = response;
      final client = LegionControlClient(transport: transport());
      await expectLater(
        client.setToggle(ControlToggle.batteryConservation, true),
        throwsA(isA<LegionControlSetupException>()),
      );
      await client.close();
    }
    expect(
      calls.any((call) => call.method == 'authorize' || call.method == 'call'),
      isFalse,
    );
  });

  test(
    'server verification failure cannot authorize or send a write',
    () async {
      handler = (_) async => throw PlatformException(
        code: 'setup',
        message: 'Root helper identity did not match.',
      );
      final client = LegionControlClient(transport: transport());
      await expectLater(
        client.setToggle(ControlToggle.batteryConservation, true),
        throwsA(isA<LegionControlSetupException>()),
      );
      expect(calls.map((call) => call.method), ['connect']);
      handler = (_) async => null;
      await client.close();
    },
  );

  test(
    'native D-Bus errors keep the existing typed client classification',
    () async {
      handler = (call) async {
        if (call.method == 'call') {
          throw PlatformException(
            code: 'io.github.prnice.LegionControl1.Error.Busy',
            message: 'another operation is active',
          );
        }
        return call.method == 'getCapabilities' ? metadata : null;
      };
      final client = LegionControlClient(transport: transport());
      addTearDown(client.close);
      await expectLater(
        client.setToggle(ControlToggle.batteryConservation, true),
        throwsA(isA<LegionControlBusyException>()),
      );
      expect(calls.where((call) => call.method == 'call'), hasLength(1));
    },
  );

  test(
    'closing an old transport uses its own session identifier only once',
    () async {
      final first = transport();
      await first.getCapabilities();
      await first.close();
      final second = transport();
      await second.getCapabilities();
      await first.close();
      await second.close();
      final connects = calls.where((call) => call.method == 'connect').toList();
      final closes = calls.where((call) => call.method == 'close').toList();
      expect(closes, hasLength(2));
      expect(
        connects[0].arguments['session'],
        isNot(connects[1].arguments['session']),
      );
      expect(closes[0].arguments['session'], connects[0].arguments['session']);
      expect(closes[1].arguments['session'], connects[1].arguments['session']);
    },
  );

  test('closing an unused transport sends no platform work', () async {
    final peer = transport();
    await peer.close();
    await peer.close();
    await expectLater(
      peer.getCapabilities(),
      throwsA(isA<LegionControlUnavailableException>()),
    );
    expect(calls, isEmpty);
  });

  test(
    'invalid payload bytes are rejected before conversion or connection',
    () async {
      final peer = transport();
      addTearDown(peer.close);
      for (final bytes in [
        [-1],
        [256],
      ]) {
        await expectLater(
          () => peer.call('ApplyFanCurve', [bytes]),
          throwsA(isA<LegionControlNotSupportedException>()),
        );
      }
      expect(calls, isEmpty);
    },
  );

  test('a build missing native support reports setup failure', () async {
    messenger.setMockMethodCallHandler(channel, null);
    final client = LegionControlClient(transport: transport());
    await expectLater(
      client.setToggle(ControlToggle.batteryConservation, true),
      throwsA(isA<LegionControlSetupException>()),
    );
    await client.close();
  });
}
