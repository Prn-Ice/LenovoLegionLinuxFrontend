import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/features/dgpu/models/graphics_mode.dart';

class _FakeTransport implements LegionControlTransport {
  final calls = <(String, List<Object>)>[];
  var authorizationCalls = 0;
  Object? callFailure;

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
  Future<void> close() async {}
}

void main() {
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
    expect(transport.calls, hasLength(commands.length * 2));
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
        ControlFeature.cpuApusPptPowerLimit: (1, 100),
        ControlFeature.gpuCtgPowerLimit: (1, 200),
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
