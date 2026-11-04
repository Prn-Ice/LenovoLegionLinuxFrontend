import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_cli_service.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/core/models/control_capabilities.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/services/legion_frontend_bridge_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockCliService extends Mock implements LegionCliService {}

class _Transport implements LegionControlTransport {
  Object? failure;
  Completer<void>? pendingAuthorization;
  final authorizationStarted = Completer<void>();
  var writes = 0;
  var closes = 0;

  @override
  Future<ControlCapabilities> getCapabilities() async => ControlCapabilities(
    protocolVersion: ControlCapabilities.currentProtocolVersion,
    supported: ControlCapability.values,
  );

  @override
  Future<void> authorize() async {
    if (!authorizationStarted.isCompleted) authorizationStarted.complete();
    await pendingAuthorization?.future;
  }

  @override
  Future<void> call(String method, List<Object> arguments) async {
    if (failure != null) throw failure!;
    writes++;
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  test(
    'write timeout closes access and prevents late authorization from writing',
    () async {
      final transport = _Transport()..pendingAuthorization = Completer<void>();
      final client = LegionControlClient(transport: transport);
      final cli = _MockCliService();
      final bridge = LegionFrontendBridgeService(
        cliService: cli,
        controlClient: client,
      );
      final timedOut = expectLater(
        bridge.runControlOperation(
          method: 'toggle',
          retries: 1,
          timeout: Duration.zero,
          operation: (client) =>
              client.setToggle(ControlToggle.hybridMode, true),
        ),
        throwsA(
          isA<LegionBridgeException>().having(
            (error) => error.code,
            'code',
            LegionBridgeErrorCode.timeout,
          ),
        ),
      );
      await transport.authorizationStarted.future;
      await timedOut;
      expect(transport.closes, 1);
      transport.pendingAuthorization!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(transport.writes, 0);
      await expectLater(
        bridge.runControlOperation(
          method: 'retry',
          operation: (client) =>
              client.setToggle(ControlToggle.hybridMode, false),
        ),
        throwsA(
          isA<LegionBridgeException>().having(
            (error) => error.code,
            'code',
            LegionBridgeErrorCode.unavailable,
          ),
        ),
      );
      expect(transport.writes, 0);
      expect(bridge.commandHistory.map((record) => record.succeeded), [
        false,
        false,
      ]);
      verifyZeroInteractions(cli);
    },
  );

  test(
    'serializes callbacks, rejects duplicates, and recovers after failure',
    () async {
      final cli = _MockCliService();
      final bridge = LegionFrontendBridgeService(
        cliService: cli,
        controlClient: LegionControlClient(transport: _Transport()),
      );
      final started = Completer<void>();
      final release = Completer<void>();
      final order = <String>[];
      final first = bridge.runControlOperation(
        method: 'first',
        args: const ['value'],
        operation: (_) async {
          order.add('first');
          started.complete();
          await release.future;
          throw const LegionControlPermissionDeniedException('denied detail');
        },
      );
      final failed = expectLater(
        first,
        throwsA(
          isA<LegionBridgeException>()
              .having(
                (e) => e.code,
                'code',
                LegionBridgeErrorCode.permissionDenied,
              )
              .having((e) => e.details, 'details', contains('denied detail')),
        ),
      );
      await started.future;
      final second = bridge.runControlOperation(
        method: 'second',
        operation: (_) async {
          order.add('second');
        },
      );
      await expectLater(
        bridge.runControlOperation(
          method: 'first',
          args: const ['value'],
          operation: (_) async {
            fail('duplicate ran');
          },
        ),
        throwsA(
          isA<LegionBridgeException>().having(
            (e) => e.code,
            'code',
            LegionBridgeErrorCode.busy,
          ),
        ),
      );
      expect(order, ['first']);
      expect(bridge.isActionPending(method: 'first', args: ['value']), isTrue);
      release.complete();
      await failed;
      await second;
      expect(order, ['first', 'second']);
      expect(bridge.isActionPending(method: 'first', args: ['value']), isFalse);
      expect(bridge.commandHistory.map((e) => e.succeeded), [false, true]);
      expect(bridge.commandHistory.every((e) => e.isPrivileged), isTrue);
      verifyZeroInteractions(cli);
    },
  );

  test(
    'timeout releases the queue and requires a fresh control session',
    () async {
      final bridge = LegionFrontendBridgeService(
        cliService: _MockCliService(),
        controlClient: LegionControlClient(transport: _Transport()),
      );
      final release = Completer<void>();
      var calls = 0;
      await expectLater(
        bridge.runControlOperation(
          method: 'slow',
          timeout: Duration.zero,
          operation: (_) {
            calls++;
            return release.future;
          },
        ),
        throwsA(
          isA<LegionBridgeException>().having(
            (e) => e.code,
            'code',
            LegionBridgeErrorCode.timeout,
          ),
        ),
      );
      await expectLater(
        bridge.runControlOperation(
          method: 'next',
          operation: (client) =>
              client.setToggle(ControlToggle.hybridMode, true),
        ),
        throwsA(
          isA<LegionBridgeException>().having(
            (error) => error.code,
            'code',
            LegionBridgeErrorCode.unavailable,
          ),
        ),
      );
      release.complete();
      expect(calls, 1);
      expect(bridge.commandHistory.map((e) => e.succeeded), [false, false]);
    },
  );

  test('retries only transient failures and bounds history', () async {
    final bridge = LegionFrontendBridgeService(
      cliService: _MockCliService(),
      controlClient: LegionControlClient(transport: _Transport()),
    );
    var calls = 0;
    await bridge.runControlOperation(
      method: 'retry',
      retries: 1,
      operation: (_) async {
        if (calls++ == 0) throw const LegionControlBusyException('busy');
      },
    );
    expect(calls, 2);
    await expectLater(
      bridge.runControlOperation(
        method: 'denied',
        retries: 1,
        operation: (_) async {
          calls++;
          throw const LegionControlPermissionDeniedException('denied');
        },
      ),
      throwsA(isA<LegionBridgeException>()),
    );
    expect(calls, 3);
    for (var i = 0; i < 21; i++) {
      await bridge.runControlOperation(method: '$i', operation: (_) async {});
    }
    expect(bridge.commandHistory, hasLength(20));
    expect(bridge.commandHistory.first.method, '1');
    expect(bridge.commandHistory.last.method, '20');
  });

  test(
    'missing control service is unavailable and never falls back to pkexec',
    () async {
      final bridge = LegionFrontendBridgeService(
        cliService: LegionCliService(cliPath: '/bin/true'),
      );

      await expectLater(
        bridge.runControlOperation(
          operation: (client) =>
              client.setFeature(ControlFeature.platformProfile, 'custom'),
          method: 'feature.set',
          args: const ['PlatformProfileFeature', 'custom'],
          retries: 0,
        ),
        throwsA(
          isA<LegionBridgeException>().having(
            (error) => error.code,
            'code',
            LegionBridgeErrorCode.privilegeSetup,
          ),
        ),
      );
    },
  );

  test(
    'privileged bridge routes supported commands to the control client',
    () async {
      final calls = <String>[];
      final transport = _RecordingTransport(calls);
      final bridge = LegionFrontendBridgeService(
        cliService: LegionCliService(cliPath: '/bin/true'),
        controlClient: LegionControlClient(transport: transport),
      );

      await bridge.runControlOperation(
        operation: (client) =>
            client.setFeature(ControlFeature.platformProfile, 'custom'),
        method: 'feature.set',
        args: const ['PlatformProfileFeature', 'custom'],
      );
      expect(calls, ['SetFeature']);
    },
  );

  test('maps control errors to bridge error codes', () async {
    final cases = <Object, LegionBridgeErrorCode>{
      const LegionControlSetupException('setup'):
          LegionBridgeErrorCode.privilegeSetup,
      const LegionControlUnavailableException('unavailable'):
          LegionBridgeErrorCode.unavailable,
      const LegionControlNotSupportedException('unsupported'):
          LegionBridgeErrorCode.unavailable,
      const LegionControlPermissionDeniedException('permission'):
          LegionBridgeErrorCode.permissionDenied,
      const LegionControlBusyException('busy'): LegionBridgeErrorCode.busy,
      const LegionControlTimeoutException('timeout'):
          LegionBridgeErrorCode.timeout,
      const LegionControlGraphicsBlockedException('blocked'):
          LegionBridgeErrorCode.graphicsBlocked,
      const LegionControlGraphicsPendingException('pending'):
          LegionBridgeErrorCode.graphicsPending,
    };
    for (final entry in cases.entries) {
      final transport = _Transport()..failure = entry.key;
      final bridge = LegionFrontendBridgeService(
        cliService: LegionCliService(cliPath: '/bin/true'),
        controlClient: LegionControlClient(transport: transport),
      );
      await expectLater(
        bridge.runControlOperation(
          operation: (client) =>
              client.setToggle(ControlToggle.hybridMode, true),
          method: 'toggle',
          args: const ['true'],
        ),
        throwsA(
          isA<LegionBridgeException>().having(
            (error) => error.code,
            'code',
            entry.value,
          ),
        ),
      );
    }

    final transport = _Transport()
      ..failure = DBusMethodResponseException(
        DBusMethodErrorResponse(
          'io.github.prnice.LegionControl1.Error.Unavailable',
        ),
      );
    final bridge = LegionFrontendBridgeService(
      cliService: LegionCliService(cliPath: '/bin/true'),
      controlClient: LegionControlClient(transport: transport),
    );
    await expectLater(
      bridge.runControlOperation(
        operation: (client) => client.setToggle(ControlToggle.hybridMode, true),
        method: 'toggle',
        args: const ['true'],
      ),
      throwsA(
        isA<LegionBridgeException>().having(
          (error) => error.code,
          'code',
          LegionBridgeErrorCode.unavailable,
        ),
      ),
    );
  });

  test(
    'does not classify diagnostic kernel timeouts as command timeouts',
    () async {
      final cli = _MockCliService();
      when(() => cli.runCommand(any())).thenAnswer(
        (_) async => const LegionCliResult(
          exitCode: 1,
          stdout: '',
          stderr:
              'amdgpu: ring gfx_0.0.0 timeout\nOSError: [Errno 22] Invalid argument',
        ),
      );
      final bridge = LegionFrontendBridgeService(cliService: cli);
      await expectLater(
        bridge.runCommand(method: 'diagnostic', args: const ['status']),
        throwsA(
          isA<LegionBridgeException>().having(
            (error) => error.code,
            'code',
            LegionBridgeErrorCode.commandFailed,
          ),
        ),
      );
    },
  );
}

class _RecordingTransport extends _Transport {
  _RecordingTransport(this.calls);
  final List<String> calls;

  @override
  Future<void> call(String method, List<Object> arguments) async {
    calls.add(method);
  }
}
