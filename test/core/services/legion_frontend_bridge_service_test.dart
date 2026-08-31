import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_cli_service.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/services/legion_frontend_bridge_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockCliService extends Mock implements LegionCliService {}

class _Transport implements LegionControlTransport {
  Object? failure;

  @override
  Future<void> authorize() async {}

  @override
  Future<void> call(String method, List<Object> arguments) async {
    if (failure != null) throw failure!;
  }

  @override
  Future<void> close() async {}
}

void main() {
  test(
    'missing control service is unavailable and never falls back to pkexec',
    () async {
      final bridge = LegionFrontendBridgeService(
        cliService: LegionCliService(cliPath: '/bin/true'),
      );

      await expectLater(
        bridge.runPrivilegedCommand(
          method: 'feature.set',
          args: const ['set-feature', 'PlatformProfileFeature', 'custom'],
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

      await bridge.runPrivilegedCommand(
        method: 'feature.set',
        args: const ['set-feature', 'PlatformProfileFeature', 'custom'],
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
        bridge.runPrivilegedCommand(
          method: 'toggle',
          args: const ['hybrid-mode-enable'],
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
      bridge.runPrivilegedCommand(
        method: 'toggle',
        args: const ['hybrid-mode-enable'],
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
