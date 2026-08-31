import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_cli_service.dart';
import 'package:legion_frontend/core/services/legion_frontend_bridge_service.dart';
import 'package:legion_frontend/features/dgpu/models/graphics_mode.dart';
import 'package:legion_frontend/features/dgpu/repository/dgpu_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockBridgeService extends Mock implements LegionFrontendBridgeService {}

void main() {
  late _MockBridgeService bridge;
  late DgpuRepository repository;

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    bridge = _MockBridgeService();
    repository = DgpuRepository(bridgeService: bridge);
  });

  test('loads authoritative combined graphics status', () async {
    when(
      () => bridge.runCommand(
        method: any(named: 'method'),
        args: any(named: 'args'),
        timeout: any(named: 'timeout'),
        detectUnavailableResponse: any(named: 'detectUnavailableResponse'),
      ),
    ).thenAnswer(
      (_) async =>
          const LegionCliResult(exitCode: 0, stdout: _statusJson, stderr: ''),
    );

    final status = await repository.loadGraphicsModeStatus();

    expect(status?.selectedMode, GraphicsMode.hybridIgpuOnly);
    expect(status?.effectiveState, DgpuTopology.detached);
    verify(
      () => bridge.runCommand(
        method: 'graphics_mode.status',
        args: ['graphics-mode', 'status', '--json'],
        timeout: const Duration(seconds: 8),
        detectUnavailableResponse: false,
      ),
    ).called(1);
  });

  test('keeps graphics status unavailable after command failure', () async {
    when(
      () => bridge.runCommand(
        method: any(named: 'method'),
        args: any(named: 'args'),
        timeout: any(named: 'timeout'),
        detectUnavailableResponse: any(named: 'detectUnavailableResponse'),
      ),
    ).thenAnswer(
      (_) async =>
          const LegionCliResult(exitCode: 1, stdout: '', stderr: 'unsupported'),
    );

    expect(await repository.loadGraphicsModeStatus(), isNull);
  });

  test('fails a required graphics status readback closed', () async {
    when(
      () => bridge.runCommand(
        method: any(named: 'method'),
        args: any(named: 'args'),
        timeout: any(named: 'timeout'),
        detectUnavailableResponse: any(named: 'detectUnavailableResponse'),
      ),
    ).thenAnswer(
      (_) async =>
          const LegionCliResult(exitCode: 1, stdout: '', stderr: 'unsupported'),
    );

    await expectLater(
      repository.loadGraphicsModeStatus(required: true),
      throwsA(
        isA<DgpuRepositoryException>().having(
          (error) => error.message,
          'message',
          contains('Authoritative graphics status could not be reloaded'),
        ),
      ),
    );
  });

  test('keeps graphics status unavailable after invalid JSON', () async {
    when(
      () => bridge.runCommand(
        method: any(named: 'method'),
        args: any(named: 'args'),
        timeout: any(named: 'timeout'),
        detectUnavailableResponse: any(named: 'detectUnavailableResponse'),
      ),
    ).thenAnswer(
      (_) async => const LegionCliResult(
        exitCode: 0,
        stdout: '{"selected_mode":"future-mode"}',
        stderr: '',
      ),
    );

    expect(await repository.loadGraphicsModeStatus(), isNull);
  });

  test(
    'sets only guarded graphics modes through the privileged bridge',
    () async {
      when(
        () => bridge.runPrivilegedCommand(
          method: any(named: 'method'),
          args: any(named: 'args'),
          timeout: any(named: 'timeout'),
          detectUnavailableResponse: any(named: 'detectUnavailableResponse'),
        ),
      ).thenAnswer((_) async {});

      await repository.setGraphicsMode(GraphicsMode.hybridIgpuOnly);

      verify(
        () => bridge.runPrivilegedCommand(
          method: 'graphics_mode.set',
          args: ['graphics-mode', 'set', 'hybrid-igpu-only'],
          timeout: const Duration(seconds: 45),
          detectUnavailableResponse: false,
        ),
      ).called(1);
      await expectLater(
        repository.setGraphicsMode(GraphicsMode.hybridAuto),
        throwsA(
          isA<DgpuRepositoryException>().having(
            (error) => error.message,
            'message',
            contains('not available as a desktop action'),
          ),
        ),
      );
    },
  );

  test('explains whether a classified graphics write changed policy', () async {
    for (final failure in const {
      LegionBridgeErrorCode.graphicsBlocked: (
        'was not changed',
        'Close GPU-accelerated applications',
      ),
      LegionBridgeErrorCode.graphicsPending: (
        'may have changed',
        'restore Hybrid from a text console',
      ),
    }.entries) {
      when(
        () => bridge.runPrivilegedCommand(
          method: any(named: 'method'),
          args: any(named: 'args'),
          timeout: any(named: 'timeout'),
          detectUnavailableResponse: any(named: 'detectUnavailableResponse'),
        ),
      ).thenThrow(
        LegionBridgeException(
          code: failure.key,
          method: 'graphics_mode.set',
          message: 'classified failure',
          stderr: 'backend detail',
        ),
      );

      await expectLater(
        repository.setGraphicsMode(GraphicsMode.hybridIgpuOnly),
        throwsA(
          isA<DgpuRepositoryException>()
              .having(
                (error) => error.message,
                'consequence',
                contains(failure.value.$1),
              )
              .having(
                (error) => error.message,
                'recovery',
                contains(failure.value.$2),
              ),
        ),
      );
      reset(bridge);
    }
  });
}

const _statusJson = '''
{
  "schema_version": 1,
  "selected_mode": "hybrid-igpu-only",
  "effective_dgpu_state": "detached",
  "expected_dgpu_state": "detached",
  "reconciliation": "settled",
  "client_inspection_complete": false,
  "active_clients": [],
  "available_modes": ["hybrid", "hybrid-igpu-only", "hybrid-auto", "discrete"]
}
''';
