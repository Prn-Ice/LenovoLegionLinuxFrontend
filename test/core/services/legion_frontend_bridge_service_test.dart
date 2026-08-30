import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_cli_service.dart';
import 'package:legion_frontend/core/services/legion_frontend_bridge_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockCliService extends Mock implements LegionCliService {}

void main() {
  test('reports missing setuid pkexec as a privilege setup error', () async {
    final cli = _MockCliService();
    when(() => cli.runCommand(any(), privileged: true)).thenAnswer(
      (_) async => const LegionCliResult(
        exitCode: 127,
        stdout: '',
        stderr: 'pkexec must be setuid root',
      ),
    );
    final bridge = LegionFrontendBridgeService(cliService: cli);

    await expectLater(
      bridge.runPrivilegedCommand(
        method: 'feature.set',
        args: const ['set-feature', 'PlatformProfileFeature', 'custom'],
        retries: 0,
      ),
      throwsA(
        isA<LegionBridgeException>()
            .having(
              (error) => error.code,
              'code',
              LegionBridgeErrorCode.privilegeSetup,
            )
            .having(
              (error) => error.details,
              'details',
              contains('security.polkit.enablePkexecWrapper'),
            ),
      ),
    );
  });

  test('accepts an explicit privileged executable', () {
    final cli = LegionCliService(
      cliPath: '/bin/true',
      privilegedExecutable: '/run/wrappers/bin/pkexec',
    );

    expect(cli.privilegedExecutable, '/run/wrappers/bin/pkexec');
  });

  test(
    'does not classify diagnostic kernel timeouts as command timeouts',
    () async {
      final cli = _MockCliService();
      when(() => cli.runCommand(any(), privileged: true)).thenAnswer(
        (_) async => const LegionCliResult(
          exitCode: 1,
          stdout: '',
          stderr: '''
amdgpu: ring gfx_0.0.0 timeout
OSError: [Errno 22] Invalid argument
''',
        ),
      );
      final bridge = LegionFrontendBridgeService(cliService: cli);

      await expectLater(
        bridge.runPrivilegedCommand(
          method: 'feature.set',
          args: const ['set-feature', 'PlatformProfileFeature', 'custom'],
          retries: 1,
        ),
        throwsA(
          isA<LegionBridgeException>()
              .having(
                (error) => error.code,
                'code',
                LegionBridgeErrorCode.commandFailed,
              )
              .having(
                (error) => error.details,
                'details',
                contains('Errno 22'),
              ),
        ),
      );

      verify(() => cli.runCommand(any(), privileged: true)).called(1);
    },
  );
}
