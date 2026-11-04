import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/data/privileged_repository.dart';
import 'package:legion_frontend/core/models/app_failure.dart';
import 'package:legion_frontend/core/services/legion_frontend_bridge_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockBridge extends Mock implements LegionFrontendBridgeService {}

/// Stand-in for a feature-specific repository exception.
class _StubException extends AppFailure {
  const _StubException(super.message, {super.kind, super.details});

  @override
  String toString() => 'StubException: $message';
}

/// Minimal concrete subclass exposing the protected helper for testing.
class _TestRepository extends PrivilegedRepository {
  const _TestRepository({required super.bridgeService});

  @override
  Exception wrapBridgeError(AppFailure failure) => _StubException(
    failure.message,
    kind: failure.kind,
    details: failure.details,
  );

  Future<void> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 5),
  }) => runControlOperation(
    (client) => client.setFeature('OverdriveFeature', '1'),
    args: args,
    method: 'feature.set',
    failurePrefix: 'Failed to apply',
    timeout: timeout,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue((LegionControlClient client) async {});
    registerFallbackValue(Duration.zero);
    registerFallbackValue(<String>[]);
  });

  late _MockBridge bridge;
  late _TestRepository repository;

  setUp(() {
    bridge = _MockBridge();
    repository = _TestRepository(bridgeService: bridge);
  });

  void stubSuccess() {
    when(
      () => bridge.runControlOperation(
        operation: any(named: 'operation'),
        method: any(named: 'method'),
        args: any(named: 'args'),
        timeout: any(named: 'timeout'),
      ),
    ).thenAnswer((_) async {});
  }

  void stubThrow(LegionBridgeException error) {
    when(
      () => bridge.runControlOperation(
        operation: any(named: 'operation'),
        method: any(named: 'method'),
        args: any(named: 'args'),
        timeout: any(named: 'timeout'),
      ),
    ).thenThrow(error);
  }

  test('forwards method and args to the bridge', () async {
    stubSuccess();

    await repository.run(['X', '1']);

    verify(
      () => bridge.runControlOperation(
        operation: any(named: 'operation'),
        method: 'feature.set',
        args: ['X', '1'],
        timeout: const Duration(seconds: 5),
      ),
    ).called(1);
  });

  test('repository timeout defaults to 5 seconds', () async {
    stubSuccess();

    await repository.run(['a']);

    final captured = verify(
      () => bridge.runControlOperation(
        operation: any(named: 'operation'),
        method: any(named: 'method'),
        args: any(named: 'args'),
        timeout: captureAny(named: 'timeout'),
      ),
    ).captured;
    expect(captured, [const Duration(seconds: 5)]);
  });

  test('forwards overridden timeout', () async {
    stubSuccess();

    await repository.run(['a'], timeout: const Duration(seconds: 10));

    verify(
      () => bridge.runControlOperation(
        operation: any(named: 'operation'),
        method: any(named: 'method'),
        args: any(named: 'args'),
        timeout: const Duration(seconds: 10),
      ),
    ).called(1);
  });

  test('wraps bridge failure with details appended to the prefix', () async {
    stubThrow(
      const LegionBridgeException(
        code: LegionBridgeErrorCode.commandFailed,
        method: 'feature.set',
        message: 'nope',
        stderr: 'boom',
      ),
    );

    await expectLater(
      repository.run(['a']),
      throwsA(
        isA<_StubException>().having(
          (e) => e.toString(),
          'message',
          'StubException: Failed to apply: boom',
        ),
      ),
    );
  });

  for (final code in LegionBridgeErrorCode.values) {
    test('preserves $code through the repository wrapper', () async {
      final error = LegionBridgeException(
        code: code,
        method: 'feature.set',
        message: 'Changed backend wording',
        stderr: 'Raw diagnostic output',
      );
      stubThrow(error);
      await expectLater(
        repository.run(['a']),
        throwsA(
          isA<_StubException>()
              .having((e) => e.kind, 'kind', AppFailure.from(error).kind)
              .having((e) => e.details, 'details', error.details),
        ),
      );
    });
  }

  test(
    'wraps bridge failure with bare prefix when details are empty',
    () async {
      stubThrow(
        const LegionBridgeException(
          code: LegionBridgeErrorCode.commandFailed,
          method: 'feature.set',
          message: 'nope',
        ),
      );

      await expectLater(
        repository.run(['a']),
        throwsA(
          isA<_StubException>().having(
            (e) => e.toString(),
            'message',
            'StubException: Failed to apply.',
          ),
        ),
      );
    },
  );
}
