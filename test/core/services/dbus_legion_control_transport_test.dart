import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/control_capabilities.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';

const _name = 'io.github.prnice.LegionControl1';

class _ControlObject extends DBusObject {
  _ControlObject() : super(DBusObjectPath('/io/github/prnice/LegionControl1'));

  final calls = <DBusMethodCall>[];
  DBusMethodResponse metadata = DBusMethodSuccessResponse([
    DBusUint32(1),
    DBusArray.string(['interactive-control', 'future-capability']),
  ]);
  Completer<void>? metadataStarted;
  Completer<DBusMethodResponse>? pendingMetadata;
  Completer<void>? authorizationStarted;
  Completer<DBusMethodResponse>? pendingAuthorization;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    calls.add(call);
    switch (call.name) {
      case 'GetCapabilities':
        metadataStarted?.complete();
        return pendingMetadata != null
            ? await pendingMetadata!.future
            : metadata;
      case 'Authorize':
        authorizationStarted?.complete();
        return pendingAuthorization != null
            ? await pendingAuthorization!.future
            : DBusMethodSuccessResponse();
      case 'SetToggle':
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

class _BusFixture {
  late DBusAddress address;
  late DBusClient service;
  final object = _ControlObject();

  Future<LegionControlClient> open() async {
    final directory = await Directory.systemTemp.createTemp('control-bus-');
    addTearDown(() => directory.delete(recursive: true));
    final server = DBusServer();
    addTearDown(server.close);
    address = await server.listenAddress(DBusAddress.unix(dir: directory));
    service = DBusClient(address);
    addTearDown(service.close);
    await service.registerObject(object);
    await service.requestName(_name);
    final client = LegionControlClient(
      transport: DBusLegionControlTransport(client: DBusClient(address)),
    );
    addTearDown(client.close);
    return client;
  }

  Future<_ControlObject> replaceService() async {
    await service.releaseName(_name);
    final replacement = DBusClient(address);
    addTearDown(replacement.close);
    final object = _ControlObject();
    await replacement.registerObject(object);
    await replacement.requestName(_name);
    return object;
  }
}

class _OpeningClient extends DBusClient {
  _OpeningClient() : super(DBusAddress('unix:path=/unused'));

  final owner = Completer<String?>();
  var closeCalls = 0;

  @override
  Future<String?> getNameOwner(String name) => owner.future;

  @override
  Future<void> close() async {
    closeCalls++;
  }
}

void main() {
  test(
    'a connection that finishes opening after disposal is closed again',
    () async {
      final bus = _OpeningClient();
      final transport = DBusLegionControlTransport(client: bus);
      final rejected = expectLater(
        transport.getCapabilities(),
        throwsA(isA<LegionControlUnavailableException>()),
      );
      await transport.close();
      bus.owner.complete(':1.2');
      await rejected;
      expect(bus.closeCalls, 2);
    },
  );

  testWidgets('lookup timeout closes a late connection before any RPC', (
    tester,
  ) async {
    final bus = _OpeningClient();
    final transport = DBusLegionControlTransport(client: bus);
    final rejected = expectLater(
      transport.getCapabilities(),
      throwsA(isA<LegionControlTimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 5));
    await rejected;
    bus.owner.complete(':1.2');
    await tester.pump();
    expect(bus.closeCalls, 2);
    await expectLater(
      transport.authorize(),
      throwsA(isA<LegionControlUnavailableException>()),
    );
  });

  test(
    'negotiates before authorization and preserves D-Bus method flags',
    () async {
      final fixture = _BusFixture();
      final client = await fixture.open();
      final capabilities = await client.getCapabilities();
      expect(capabilities.protocolVersion, 1);
      expect(capabilities.supported, {ControlCapability.interactiveControl});
      await client.setToggle(ControlToggle.hybridMode, true);
      expect(fixture.object.calls.map((call) => call.name), [
        'GetCapabilities',
        'Authorize',
        'SetToggle',
      ]);
      expect(
        fixture.object.calls.map((call) => call.allowInteractiveAuthorization),
        [false, true, false],
      );
      expect(fixture.object.calls.every((call) => call.noAutoStart), isTrue);
      expect(fixture.object.calls.last.values, [
        DBusString('hybrid-mode'),
        DBusBoolean(true),
      ]);
    },
  );

  test(
    'older and malformed helpers receive no authorization or writes',
    () async {
      for (final response in [
        DBusMethodErrorResponse.unknownMethod(),
        DBusMethodSuccessResponse([DBusString('wrong-signature')]),
      ]) {
        final fixture = _BusFixture();
        final client = await fixture.open();
        fixture.object.metadata = response;
        await expectLater(
          client.setToggle(ControlToggle.hybridMode, true),
          throwsA(isA<LegionControlSetupException>()),
        );
        expect(fixture.object.calls.map((call) => call.name), [
          'GetCapabilities',
        ]);
      }
    },
  );

  test('a replacement service cannot inherit cached capabilities', () async {
    final fixture = _BusFixture();
    final client = await fixture.open();
    await client.getCapabilities();
    final replacement = await fixture.replaceService();
    await expectLater(
      client.setToggle(ControlToggle.hybridMode, true),
      throwsA(isA<LegionControlUnavailableException>()),
    );
    expect(fixture.object.calls.map((call) => call.name), ['GetCapabilities']);
    expect(replacement.calls, isEmpty);
  });

  test(
    'service replacement after authorization cannot receive a write',
    () async {
      final fixture = _BusFixture();
      final client = await fixture.open();
      await client.setToggle(ControlToggle.hybridMode, true);
      final replacement = await fixture.replaceService();
      await expectLater(
        client.setToggle(ControlToggle.hybridMode, false),
        throwsA(isA<LegionControlUnavailableException>()),
      );
      expect(
        fixture.object.calls.where((call) => call.name == 'SetToggle'),
        hasLength(1),
      );
      expect(replacement.calls, isEmpty);
    },
  );

  test('replacement during authorization blocks the queued write', () async {
    final fixture = _BusFixture();
    final client = await fixture.open();
    fixture.object.authorizationStarted = Completer<void>();
    fixture.object.pendingAuthorization = Completer<DBusMethodResponse>();
    final rejected = expectLater(
      client.setToggle(ControlToggle.hybridMode, true),
      throwsA(isA<LegionControlUnavailableException>()),
    );
    await fixture.object.authorizationStarted!.future;
    final replacement = await fixture.replaceService();
    fixture.object.pendingAuthorization!.complete(DBusMethodSuccessResponse());
    await rejected;
    expect(fixture.object.calls.map((call) => call.name), [
      'GetCapabilities',
      'Authorize',
    ]);
    expect(replacement.calls, isEmpty);
  });

  test('closing while metadata is pending prevents authorization', () async {
    final fixture = _BusFixture();
    final client = await fixture.open();
    fixture.object.metadataStarted = Completer<void>();
    fixture.object.pendingMetadata = Completer<DBusMethodResponse>();
    final rejected = expectLater(
      client.setToggle(ControlToggle.hybridMode, true),
      throwsA(isA<LegionControlUnavailableException>()),
    );
    await fixture.object.metadataStarted!.future;
    await client.close();
    fixture.object.pendingMetadata!.complete(fixture.object.metadata);
    await rejected;
    expect(fixture.object.calls.map((call) => call.name), ['GetCapabilities']);
  });
}
