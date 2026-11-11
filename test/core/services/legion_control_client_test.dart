import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/control_capabilities.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/features/dgpu/models/graphics_mode.dart';

class _FakeTransport extends LegionControlTransport {
  final calls = <(String, List<Object>)>[];
  var authorizationCalls = 0;
  var capabilityCalls = 0;
  var closeCalls = 0;
  var capabilities = ControlCapabilities(
    protocolVersion: ControlCapabilities.currentProtocolVersion,
    supported: ControlCapability.values,
  );
  Future<ControlCapabilities>? pendingCapabilities;
  Object? capabilityFailure;
  Object? callFailure;
  Completer<void>? pendingPreparation;
  final preparationStarted = Completer<void>();
  final metadataStarted = Completer<void>();

  @override
  Future<void> prepare() async {
    if (!preparationStarted.isCompleted) preparationStarted.complete();
    await pendingPreparation?.future;
  }

  @override
  Future<ControlCapabilities> getCapabilities() async {
    capabilityCalls++;
    if (!metadataStarted.isCompleted) metadataStarted.complete();
    if (capabilityFailure != null) throw capabilityFailure!;
    return pendingCapabilities != null
        ? await pendingCapabilities!
        : capabilities;
  }

  @override
  Future<void> authorize() async {
    authorizationCalls++;
  }

  @override
  Future<void> call(String method, List<Object> arguments) async {
    if (callFailure != null) throw callFailure!;
    calls.add((method, arguments));
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }
}

void main() {
  test('closing during startup prevents metadata and authorization', () async {
    final transport = _FakeTransport()..pendingPreparation = Completer<void>();
    final client = LegionControlClient(transport: transport);
    final rejected = expectLater(
      client.setToggle(ControlToggle.hybridMode, true),
      throwsA(isA<LegionControlUnavailableException>()),
    );
    await transport.preparationStarted.future;
    await client.close();
    await rejected;
    transport.pendingPreparation!.complete();
    expect(transport.capabilityCalls, 0);
    expect(transport.authorizationCalls, 0);
  });

  test('startup approval has its own budget before metadata timeout', () async {
    final transport = _FakeTransport()..pendingPreparation = Completer<void>();
    final client = LegionControlClient(
      transport: transport,
      metadataTimeout: Duration.zero,
    );
    final writing = client.setToggle(ControlToggle.hybridMode, true);
    await transport.preparationStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(transport.capabilityCalls, 0);
    expect(transport.closeCalls, 0);
    transport.pendingPreparation!.complete();
    await writing;
    await client.close();
    expect(transport.calls, hasLength(1));
  });

  test(
    'checks capabilities once before concurrent authorization and writes',
    () async {
      final transport = _FakeTransport();
      final metadata = Completer<ControlCapabilities>();
      transport.pendingCapabilities = metadata.future;
      final client = LegionControlClient(transport: transport);
      addTearDown(client.close);
      final writes = Future.wait([
        client.setToggle(ControlToggle.hybridMode, true),
        client.applyFanPreset(ControlFanPreset.quietAc),
      ]);
      await transport.metadataStarted.future;
      expect(transport.capabilityCalls, 1);
      expect(transport.authorizationCalls, 0);
      expect(transport.calls, isEmpty);
      metadata.complete(transport.capabilities);
      await writes;
      await client.setToggle(ControlToggle.hybridMode, false);
      expect(transport.capabilityCalls, 1);
      expect(transport.authorizationCalls, 1);
      expect(transport.calls, hasLength(3));
    },
  );

  test('reading capabilities never requests authorization', () async {
    final transport = _FakeTransport();
    final client = LegionControlClient(transport: transport);
    addTearDown(client.close);
    await client.getCapabilities();
    expect(transport.authorizationCalls, 0);
    expect(transport.calls, isEmpty);
  });

  test(
    'incompatible and incomplete helpers cannot authorize or write',
    () async {
      for (final capabilities in [
        ControlCapabilities(
          protocolVersion: 2,
          supported: ControlCapability.values,
        ),
        ControlCapabilities(protocolVersion: 1, supported: const []),
      ]) {
        final transport = _FakeTransport()..capabilities = capabilities;
        final client = LegionControlClient(transport: transport);
        addTearDown(client.close);
        await expectLater(
          client.setToggle(ControlToggle.hybridMode, true),
          throwsA(isA<LegionControlSetupException>()),
        );
        expect(transport.authorizationCalls, 0);
        expect(transport.calls, isEmpty);
      }
    },
  );

  test('older helper reports update guidance before authorization', () async {
    final transport = _FakeTransport()
      ..capabilityFailure = DBusMethodResponseException(
        DBusMethodErrorResponse.unknownMethod(),
      );
    final client = LegionControlClient(transport: transport);
    addTearDown(client.close);
    await expectLater(
      client.setToggle(ControlToggle.hybridMode, true),
      throwsA(
        isA<LegionControlSetupException>().having(
          (error) => error.message,
          'message',
          contains('Update the app and control helper together'),
        ),
      ),
    );
    expect(transport.authorizationCalls, 0);
    expect(transport.calls, isEmpty);
  });

  test(
    'interactive helper refuses persistent writes before authorization',
    () async {
      final transport = _FakeTransport()
        ..capabilities = ControlCapabilities(
          protocolVersion: 1,
          supported: const [ControlCapability.interactiveControl],
        );
      final client = LegionControlClient(transport: transport);
      addTearDown(client.close);
      await expectLater(
        client.setServiceEnabled(ControlService.legiondStack, true),
        throwsA(isA<LegionControlNotSupportedException>()),
      );
      expect(transport.authorizationCalls, 0);
      expect(transport.calls, isEmpty);
      await client.setToggle(ControlToggle.hybridMode, true);
      expect(transport.calls.single.$1, 'SetToggle');
    },
  );

  test('failed metadata can be retried without caching its failure', () async {
    final transport = _FakeTransport()
      ..capabilityFailure = const LegionControlUnavailableException('offline');
    final client = LegionControlClient(transport: transport);
    addTearDown(client.close);
    await expectLater(
      client.setToggle(ControlToggle.hybridMode, true),
      throwsA(isA<LegionControlUnavailableException>()),
    );
    transport.capabilityFailure = null;
    await client.setToggle(ControlToggle.hybridMode, true);
    expect(transport.capabilityCalls, 2);
    expect(transport.authorizationCalls, 1);
    expect(transport.calls, hasLength(1));
  });

  test(
    'closing during metadata prevents later authorization and writes',
    () async {
      final transport = _FakeTransport();
      final metadata = Completer<ControlCapabilities>();
      transport.pendingCapabilities = metadata.future;
      final client = LegionControlClient(transport: transport);
      final rejected = expectLater(
        client.setToggle(ControlToggle.hybridMode, true),
        throwsA(isA<LegionControlUnavailableException>()),
      );
      await client.close();
      await client.close();
      metadata.complete(transport.capabilities);
      await rejected;
      expect(transport.closeCalls, 1);
      expect(transport.authorizationCalls, 0);
      expect(transport.calls, isEmpty);
    },
  );

  test('closing during authorization prevents the pending write', () async {
    final transport = _PendingAuthorizationTransport();
    final client = LegionControlClient(transport: transport);
    final rejected = expectLater(
      client.setToggle(ControlToggle.hybridMode, true),
      throwsA(isA<LegionControlUnavailableException>()),
    );
    await transport.started.future;
    await client.close();
    transport.authorization.complete();
    await rejected;
    expect(transport.calls, isEmpty);
  });

  test(
    'metadata timeout closes the session and rejects a late reply',
    () async {
      final transport = _FakeTransport();
      final metadata = Completer<ControlCapabilities>();
      transport.pendingCapabilities = metadata.future;
      final client = LegionControlClient(
        transport: transport,
        metadataTimeout: Duration.zero,
      );
      final rejected = expectLater(
        client.setToggle(ControlToggle.hybridMode, true),
        throwsA(isA<LegionControlTimeoutException>()),
      );
      await rejected;
      metadata.complete(transport.capabilities);
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        client.getCapabilities(),
        throwsA(isA<LegionControlUnavailableException>()),
      );
      expect(transport.closeCalls, 1);
      expect(transport.authorizationCalls, 0);
      expect(transport.calls, isEmpty);
    },
  );

  test(
    'maps feature, toggles, fan, conservation and restore commands',
    () async {
      final transport = _FakeTransport();
      final client = LegionControlClient(transport: transport);

      await client.setFeature(ControlFeature.overdrive, '1');
      await client.setToggle(ControlToggle.hybridMode, false);
      await client.applyFanPreset(ControlFanPreset.quietAc);
      await client.applyCustomConservation(40, 80);
      await client.restoreBootLogo();

      expect(transport.calls.map((call) => call.$1), [
        'SetFeature',
        'SetToggle',
        'ApplyFanPreset',
        'ApplyCustomConservation',
        'RestoreBootLogo',
      ]);
      expect(transport.calls[1].$2, ['hybrid-mode', false]);
    },
  );

  test('rejects unsupported commands before transport', () async {
    final transport = _FakeTransport();
    final client = LegionControlClient(transport: transport);

    expect(
      () => client.setFeature(ControlFeature.cpuLongtermPowerLimit, '01'),
      throwsA(isA<LegionControlNotSupportedException>()),
    );
    expect(transport.authorizationCalls, 0);
    expect(transport.calls, isEmpty);
  });

  test('supports every allow-listed toggle', () async {
    final transport = _FakeTransport();
    final client = LegionControlClient(transport: transport);
    const commands = ControlToggle.values;

    for (final command in commands) {
      await client.setToggle(command, true);
      await client.setToggle(command, false);
    }
    expect(transport.calls.map((call) => [call.$1, ...call.$2]), [
      for (final name in const [
        'hybrid-mode',
        'battery-conservation',
        'rapid-charging',
        'always-on-usb-charging',
        'touchpad',
        'fn-lock',
        'mini-fan-curve',
        'lock-fan-controller',
        'maximum-fan-speed',
      ]) ...[
        ['SetToggle', name, true],
        ['SetToggle', name, false],
      ],
    ]);
  });

  test('fan preset enums keep the backend preset names', () async {
    final transport = _FakeTransport();
    final client = LegionControlClient(transport: transport);
    for (final preset in ControlFanPreset.values) {
      await client.applyFanPreset(preset);
    }
    expect(transport.calls.map((call) => [call.$1, ...call.$2]), [
      for (final name in const [
        'quiet-battery',
        'balanced-battery',
        'performance-battery',
        'balanced-performance-battery',
        'quiet-ac',
        'balanced-ac',
        'performance-ac',
        'balanced-performance-ac',
      ])
        ['ApplyFanPreset', name],
    ]);
  });

  test('feature enums keep the backend setting names', () async {
    final transport = _FakeTransport();
    final client = LegionControlClient(transport: transport);
    for (final feature in ControlFeature.values) {
      await client.setFeature(feature, switch (feature) {
        ControlFeature.platformProfile => 'balanced',
        ControlFeature.cpuLongtermPowerLimit ||
        ControlFeature.cpuShorttermPowerLimit => '5',
        _ => '1',
      });
    }
    expect(transport.calls.map((call) => call.$2.first), [
      'PlatformProfileFeature',
      'OverdriveFeature',
      'WinkeyFeature',
      'CPULongtermPowerLimit',
      'CPUShorttermPowerLimit',
      'CPUPeakPowerLimit',
      'CPUCrossLoadingPowerLimit',
      'CPUAPUSPPTPowerLimit',
      'GPUCTGPPowerLimit',
      'GPUPPABPowerLimit',
      'GPUBoostClock',
      'GPUTemperatureLimit',
      'CPUOverclock',
      'GPUOverclock',
      'YLogoLight',
      'IOPortLight',
    ]);
  });

  test('maps only guarded graphics modes to the typed method', () async {
    final transport = _FakeTransport();
    final client = LegionControlClient(transport: transport);

    for (final mode in const [
      GraphicsMode.hybrid,
      GraphicsMode.hybridIgpuOnly,
      GraphicsMode.discrete,
    ]) {
      await client.setGraphicsMode(mode);
    }

    expect(transport.calls.map((call) => call.$1), [
      'SetGraphicsMode',
      'SetGraphicsMode',
      'SetGraphicsMode',
    ]);
    expect(transport.calls.map((call) => call.$2.single), [
      'hybrid',
      'hybrid-igpu-only',
      'discrete',
    ]);
    await expectLater(
      () => client.setGraphicsMode(GraphicsMode.hybridAuto),
      throwsA(isA<LegionControlNotSupportedException>()),
    );
  });

  test('validates service IDs and byte payload boundaries', () async {
    final transport = _FakeTransport();
    final client = LegionControlClient(transport: transport);
    await client.setServiceEnabled(ControlService.powerProfilesDaemon, true);
    await client.setServiceEnabled(ControlService.legiondStack, false);
    expect(transport.calls.map((call) => [call.$1, ...call.$2]), [
      ['SetServiceEnabled', 'power_profiles_daemon', true],
      ['SetServiceEnabled', 'legiond_stack', false],
    ]);
    await client.applyFanCurve([0, 255]);
    expect(
      () => client.applyFanCurve([-1]),
      throwsA(isA<LegionControlNotSupportedException>()),
    );
    expect(
      () => client.setBootLogo([256]),
      throwsA(isA<LegionControlNotSupportedException>()),
    );
  });

  test('maps D-Bus InvalidArgs and unavailable errors centrally', () async {
    final transport = _FakeTransport();
    final client = LegionControlClient(transport: transport);
    final failures = <DBusMethodErrorResponse, Type>{
      DBusMethodErrorResponse.invalidArgs(): LegionControlNotSupportedException,
      DBusMethodErrorResponse(
        'io.github.prnice.LegionControl1.Error.Unavailable',
      ): LegionControlUnavailableException,
      DBusMethodErrorResponse('org.freedesktop.DBus.Error.ServiceUnknown'):
          LegionControlSetupException,
    };
    for (final entry in failures.entries) {
      final response = entry.key;
      transport.callFailure = DBusMethodResponseException(response);
      await expectLater(
        client.setToggle(ControlToggle.hybridMode, true),
        throwsA(
          isA<LegionControlException>().having(
            (error) => error.runtimeType,
            'type',
            entry.value,
          ),
        ),
      );
      transport.callFailure = null;
    }
  });

  test('maps classified graphics errors centrally', () async {
    final transport = _FakeTransport();
    final client = LegionControlClient(transport: transport);
    final failures = <String, Type>{
      'io.github.prnice.LegionControl1.Error.GraphicsBlocked':
          LegionControlGraphicsBlockedException,
      'io.github.prnice.LegionControl1.Error.GraphicsPending':
          LegionControlGraphicsPendingException,
    };

    for (final entry in failures.entries) {
      transport.callFailure = DBusMethodResponseException(
        DBusMethodErrorResponse(entry.key),
      );
      await expectLater(
        client.setGraphicsMode(GraphicsMode.hybridIgpuOnly),
        throwsA(
          isA<LegionControlException>().having(
            (error) => error.runtimeType,
            'type',
            entry.value,
          ),
        ),
      );
    }
  });

  test(
    'accepts canonical feature values only at every range boundary',
    () async {
      final transport = _FakeTransport();
      final client = LegionControlClient(transport: transport);
      const ranges = {
        ControlFeature.cpuLongtermPowerLimit: (5, 200),
        ControlFeature.cpuShorttermPowerLimit: (5, 200),
        ControlFeature.cpuPeakPowerLimit: (1, 200),
        ControlFeature.cpuCrossLoadingPowerLimit: (1, 100),
        ControlFeature.cpuApuSpptPowerLimit: (1, 100),
        ControlFeature.gpuCtgpPowerLimit: (1, 200),
        ControlFeature.gpuPpabPowerLimit: (1, 200),
        ControlFeature.gpuBoostClock: (1, 10000),
        ControlFeature.gpuTemperatureLimit: (1, 120),
      };
      for (final entry in ranges.entries) {
        await client.setFeature(entry.key, '${entry.value.$1}');
        await client.setFeature(entry.key, '${entry.value.$2}');
        expect(
          () => client.setFeature(entry.key, '01'),
          throwsA(isA<LegionControlNotSupportedException>()),
        );
        expect(
          () => client.setFeature(entry.key, '${entry.value.$2 + 1}'),
          throwsA(isA<LegionControlNotSupportedException>()),
        );
      }
    },
  );

  test(
    'reauthorizes and retries after the service loses its sender cache',
    () async {
      final transport = _AuthorizationLossTransport();
      final client = LegionControlClient(transport: transport);

      await client.setToggle(ControlToggle.hybridMode, true);

      expect(transport.authorizationCalls, 2);
      expect(transport.calls, hasLength(1));
      expect(transport.calls.single.$1, 'SetToggle');
      expect(transport.calls.single.$2, ['hybrid-mode', true]);
    },
  );

  test('reauthorizes after a generic transport failure', () async {
    final transport = _FakeTransport();
    final client = LegionControlClient(transport: transport);
    transport.callFailure = StateError('connection lost');

    await expectLater(
      client.setToggle(ControlToggle.hybridMode, true),
      throwsA(isA<StateError>()),
    );
    transport.callFailure = null;
    await client.setToggle(ControlToggle.hybridMode, false);

    expect(transport.authorizationCalls, 2);
    expect(transport.calls, hasLength(1));
  });

  test('closed D-Bus transport rejects authorization and calls', () async {
    final transport = DBusLegionControlTransport();
    await transport.close();
    await expectLater(
      transport.getCapabilities(),
      throwsA(isA<LegionControlUnavailableException>()),
    );
    await expectLater(
      transport.authorize(),
      throwsA(isA<LegionControlUnavailableException>()),
    );
    await expectLater(
      transport.call('SetToggle', const ['hybrid-mode', true]),
      throwsA(isA<LegionControlUnavailableException>()),
    );
  });

  test('payload operations transfer bytes', () async {
    final transport = _FakeTransport();
    final client = LegionControlClient(transport: transport);

    await client.applyFanCurve([1, 2, 255]);
    await client.setBootLogo([1, 2, 255]);

    expect(transport.calls[0].$2.single, [1, 2, 255]);
    expect(transport.calls[1].$2.single, [1, 2, 255]);
  });

  test(
    'concurrent first calls authorize once and denial can be retried',
    () async {
      final transport = _RetryTransport();
      final client = LegionControlClient(transport: transport);
      final first = Future.wait<void>([
        client.setFeature(ControlFeature.overdrive, '1'),
        client.setToggle(ControlToggle.hybridMode, true),
      ]);
      await Future<void>.delayed(Duration.zero);
      transport.releaseFirstAuthorization();
      await expectLater(
        first,
        throwsA(isA<LegionControlPermissionDeniedException>()),
      );
      await client.setFeature(ControlFeature.overdrive, '0');
      expect(transport.calls.length, 1);
      expect(transport.authorizationCalls, 2);
    },
  );
}

class _PendingAuthorizationTransport extends _FakeTransport {
  final started = Completer<void>();
  final authorization = Completer<void>();

  @override
  Future<void> authorize() {
    authorizationCalls++;
    started.complete();
    return authorization.future;
  }
}

class _RetryTransport extends _FakeTransport {
  final _firstAuthorization = Completer<void>();
  var _first = true;

  @override
  Future<void> authorize() async {
    authorizationCalls++;
    if (_first) {
      _first = false;
      await _firstAuthorization.future;
      throw const LegionControlPermissionDeniedException('denied');
    }
  }

  void releaseFirstAuthorization() => _firstAuthorization.complete();
}

class _AuthorizationLossTransport extends _FakeTransport {
  var _hasLostAuthorization = false;

  @override
  Future<void> call(String method, List<Object> arguments) async {
    if (!_hasLostAuthorization) {
      _hasLostAuthorization = true;
      throw DBusMethodResponseException(DBusMethodErrorResponse.accessDenied());
    }
    await super.call(method, arguments);
  }
}
