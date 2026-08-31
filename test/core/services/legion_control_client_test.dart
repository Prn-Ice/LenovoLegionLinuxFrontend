import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';

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

      await client.runCommand(const ['set-feature', 'OverdriveFeature', '1']);
      await client.runCommand(const ['hybrid-mode-disable']);
      await client.runCommand(const [
        'fancurve-write-preset-to-hw',
        'quiet-ac',
      ]);
      await client.runCommand(const [
        'custom-conservation-mode-apply',
        '40',
        '80',
      ]);
      await client.runCommand(const ['boot-logo', 'restore']);

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

    await expectLater(
      client.runCommand(const ['camera', 'on']),
      throwsA(isA<LegionControlNotSupportedException>()),
    );
    await expectLater(
      client.runCommand(const [
        'set-feature',
        'WhiteKeyboardBacklightFeature',
        '1',
      ]),
      throwsA(isA<LegionControlNotSupportedException>()),
    );
    expect(transport.calls, isEmpty);
  });

  test('supports every toggle command and rejects extra arguments', () async {
    final transport = _FakeTransport();
    final client = LegionControlClient(transport: transport);
    const commands = [
      'hybrid-mode',
      'batteryconservation',
      'rapid-charging',
      'minifancurve',
      'lockfancontroller',
      'maximumfanspeed',
      'always-on-usb-charging',
      'touchpad',
      'fnlock',
    ];

    for (final command in commands) {
      await client.runCommand(['$command-enable']);
      await client.runCommand(['$command-disable']);
    }
    expect(transport.calls, hasLength(commands.length * 2));
    await expectLater(
      client.runCommand(const ['hybrid-mode-enable', 'extra']),
      throwsA(isA<LegionControlNotSupportedException>()),
    );
    await expectLater(
      client.runCommand(const [
        'set-feature',
        'OverdriveFeature',
        '1',
        'extra',
      ]),
      throwsA(isA<LegionControlNotSupportedException>()),
    );
  });

  test('validates service IDs and byte payload boundaries', () async {
    final transport = _FakeTransport();
    final client = LegionControlClient(transport: transport);
    await client.setServiceEnabled('power_profiles_daemon', true);
    await client.setServiceEnabled('legiond_stack', false);
    expect(
      () => client.setServiceEnabled('other', true),
      throwsA(isA<LegionControlNotSupportedException>()),
    );
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
        client.setToggle('hybrid-mode', true),
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

  test(
    'accepts canonical feature values only at every range boundary',
    () async {
      final transport = _FakeTransport();
      final client = LegionControlClient(transport: transport);
      const ranges = {
        'CPULongtermPowerLimit': (5, 200),
        'CPUShorttermPowerLimit': (5, 200),
        'CPUPeakPowerLimit': (1, 200),
        'CPUCrossLoadingPowerLimit': (1, 100),
        'CPUAPUSPPTPowerLimit': (1, 100),
        'CPUDefaultPowerLimit': (1, 100),
        'GPUCTGPPowerLimit': (1, 200),
        'GPUPPABPowerLimit': (1, 200),
        'GPUBoostClock': (1, 10000),
        'GPUTemperatureLimit': (1, 120),
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

      await client.setToggle('hybrid-mode', true);

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
      client.setToggle('hybrid-mode', true),
      throwsA(isA<StateError>()),
    );
    transport.callFailure = null;
    await client.setToggle('hybrid-mode', false);

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

  test('file commands transfer bytes', () async {
    final transport = _FakeTransport();
    final client = LegionControlClient(
      transport: transport,
      bytesReader: (_) async => [1, 2, 255],
    );

    await client.runCommand(const ['fancurve-write-file-to-hw', '/tmp/curve']);
    await client.runCommand(const ['boot-logo', 'enable', '/tmp/logo']);

    expect(transport.calls[0].$2.single, [1, 2, 255]);
    expect(transport.calls[1].$2.single, [1, 2, 255]);
  });

  test(
    'concurrent first calls authorize once and denial can be retried',
    () async {
      final transport = _RetryTransport();
      final client = LegionControlClient(transport: transport);
      final first = Future.wait<void>([
        client.setFeature('OverdriveFeature', '1'),
        client.setToggle('hybrid-mode', true),
      ]);
      await Future<void>.delayed(Duration.zero);
      transport.releaseFirstAuthorization();
      await expectLater(
        first,
        throwsA(isA<LegionControlPermissionDeniedException>()),
      );
      await client.setFeature('OverdriveFeature', '0');
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
