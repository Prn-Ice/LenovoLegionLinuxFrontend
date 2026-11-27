import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/control_endpoint.dart';
import 'package:legion_frontend/core/services/control_launcher.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/services/package_power_telemetry_service.dart';

class _Launcher extends Fake implements ControlLauncher {
  _Launcher(this._start);

  final Future<ControlEndpoint> Function() _start;
  int stops = 0;

  @override
  Future<ControlEndpoint> start() => _start();

  @override
  Future<void> close() async => stops++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sensor polling before approval leaves the helper stopped', () async {
    var launches = 0;
    final client = SessionPackagePowerClient(
      createLauncher: () {
        launches++;
        throw StateError('Unexpected launch');
      },
    );
    expect(await client.readPackagePowerWatts(), isNull);
    expect(launches, 0);
    await client.close();
  });

  test('approval can be retried after denial and after stopping readings', () async {
    const endpoint = ControlEndpoint(
      address: 'unix:path=/run/legion-example/control.sock',
      unit:
          'legion-bootstrap-probe-01234567-89ab-4cde-8fab-0123456789ab.service',
      helperPid: 123,
      busName: ':1.23',
    );
    final launchers = [
      _Launcher(
        () async =>
            throw const LegionControlStartupDeniedException('Cancelled'),
      ),
      _Launcher(() async => endpoint),
      _Launcher(() async => endpoint),
    ];
    var launches = 0;
    final client = SessionPackagePowerClient(
      createLauncher: () => launchers[launches++],
    );
    const channel = MethodChannel('io.github.prnice.legion/package_power');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    final readingStarted = Completer<void>();
    final reading = Completer<double>();
    var pendingRead = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method != 'readPackagePower') return null;
      if (!pendingRead) return 23.5;
      readingStarted.complete();
      return reading.future;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    addTearDown(client.close);

    await expectLater(
      client.enable(),
      throwsA(isA<LegionControlStartupDeniedException>()),
    );
    expect(launchers[0].stops, 1);
    expect(await client.readPackagePowerWatts(), isNull);
    expect(calls, isEmpty);

    await client.enable();
    expect(await client.readPackagePowerWatts(), 23.5);
    pendingRead = true;
    final inFlight = client.readPackagePowerWatts();
    await readingStarted.future;
    await client.disable();
    reading.complete(99);
    expect(await inFlight, isNull);
    expect(await client.readPackagePowerWatts(), isNull);
    expect(launchers[1].stops, 1);
    expect(calls, ['connect', 'readPackagePower', 'readPackagePower', 'close']);

    await client.enable();
    pendingRead = false;
    expect(await client.readPackagePowerWatts(), 23.5);
    expect(launches, 3);
    await client.close();
    expect(launchers[2].stops, 1);
  });
}
