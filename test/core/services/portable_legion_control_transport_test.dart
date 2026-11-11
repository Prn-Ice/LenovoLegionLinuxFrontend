import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/control_capabilities.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/services/portable_control_launcher.dart';
import 'package:legion_frontend/core/services/portable_legion_control_transport.dart';

import '../../support/portable_helper_process.dart';

class _Peer extends LegionControlTransport {
  final calls = <String>[];
  var closes = 0;
  var version = 1;
  Object? metadataFailure;
  @override
  Future<ControlCapabilities> getCapabilities() async {
    calls.add('metadata');
    if (metadataFailure != null) throw metadataFailure!;
    return ControlCapabilities(
      protocolVersion: version,
      supported: const [ControlCapability.interactiveControl],
    );
  }

  @override
  Future<void> authorize() async {
    calls.add('authorize');
  }

  @override
  Future<void> call(String method, List<Object> arguments) async {
    calls.add(method);
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  late PortableHelperProcess process;
  late PortableControlLauncher launcher;
  late _Peer peer;
  late LegionControlClient client;
  var connections = 0;
  setUp(() {
    process = PortableHelperProcess();
    peer = _Peer();
    connections = 0;
    launcher = PortableControlLauncher(
      executable: '/bundle/helper',
      startProcess:
          (
            _,
            _, {
            required environment,
            required workingDirectory,
            required includeParentEnvironment,
          }) async => process,
    );
    client = LegionControlClient(
      transport: PortableLegionControlTransport(
        launcher: launcher,
        connect: (endpoint) {
          connections++;
          expect(endpoint.address, portableTestAddress);
          return peer;
        },
      ),
    );
  });
  tearDown(() => client.close());

  test('starts one launcher before metadata and typed writes', () async {
    final writing = Future.wait([
      client.setToggle(ControlToggle.batteryConservation, true),
      client.setToggle(ControlToggle.rapidCharging, false),
    ]);
    await process.listening.future;
    expect(connections, 0);
    process.ready();
    await writing;
    expect(connections, 1);
    expect(peer.calls, ['metadata', 'authorize', 'SetToggle', 'SetToggle']);
    await client.close();
    expect(process.signals, [ProcessSignal.sigterm]);
    expect(peer.closes, 1);
  });

  test('closing before readiness prevents creating a peer', () async {
    final rejected = expectLater(
      client.setToggle(ControlToggle.batteryConservation, true),
      throwsA(isA<LegionControlUnavailableException>()),
    );
    await process.listening.future;
    await client.close();
    await rejected;
    expect(connections, 0);
    expect(process.signals, [ProcessSignal.sigterm]);
  });

  test('helper exit after readiness closes the existing peer', () async {
    final metadata = client.getCapabilities();
    await process.listening.future;
    process.ready();
    await metadata;
    process.finish(1);
    await launcher.ended;
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      client.setToggle(ControlToggle.batteryConservation, true),
      throwsA(isA<LegionControlUnavailableException>()),
    );
    expect(peer.closes, 1);
    expect(peer.calls, ['metadata']);
  });

  test(
    'incompatible helper protocol stops the child before authorization',
    () async {
      peer.version = 2;
      final rejected = expectLater(
        client.setToggle(ControlToggle.batteryConservation, true),
        throwsA(isA<LegionControlSetupException>()),
      );
      await process.listening.future;
      process.ready();
      await rejected;
      expect(peer.calls, ['metadata']);
      expect(peer.closes, 1);
      expect(process.signals, [ProcessSignal.sigterm]);
    },
  );

  test('metadata failure closes both owned resources', () async {
    peer.metadataFailure = const LegionControlUnavailableException(
      'connection failed',
    );
    final rejected = expectLater(
      client.getCapabilities(),
      throwsA(isA<LegionControlUnavailableException>()),
    );
    await process.listening.future;
    process.ready();
    await rejected;
    expect(peer.closes, 1);
    expect(process.signals, [ProcessSignal.sigterm]);
  });

  test('supervises a real ordinary-user child that ignores SIGTERM', () async {
    Process? child;
    final owner = PortableControlLauncher(
      executable: '/bundle/helper',
      stopTimeout: const Duration(milliseconds: 50),
      startProcess:
          (
            _,
            _, {
            required environment,
            required workingDirectory,
            required includeParentEnvironment,
          }) async {
            return child = await Process.start(
              '/bin/sh',
              [File('test/fixtures/portable_launcher.sh').absolute.path],
              environment: environment,
              workingDirectory: workingDirectory,
              includeParentEnvironment: includeParentEnvironment,
            );
          },
    );
    addTearDown(owner.close);
    final endpoint = await owner.start();
    expect(endpoint.unit, portableTestUnit);
    await owner.close();
    expect(await child!.exitCode, -ProcessSignal.sigkill.signalNumber);
  });
}
