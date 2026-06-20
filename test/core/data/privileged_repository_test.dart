import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/data/privileged_repository.dart';
import 'package:legion_frontend/core/services/legion_frontend_bridge_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockBridge extends Mock implements LegionFrontendBridgeService {}

/// Stand-in for a feature-specific repository exception.
class _StubException implements Exception {
  const _StubException(this.message);

  final String message;

  @override
  String toString() => 'StubException: $message';
}

/// Minimal concrete subclass exposing the protected helper for testing.
class _TestRepository extends PrivilegedRepository {
  const _TestRepository({required super.bridgeService});

  @override
  Exception wrapBridgeError(String message) => _StubException(message);

  Future<void> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 5),
    bool detectUnavailableResponse = true,
  }) => runPrivilegedCommand(
    args,
    method: 'feature.set',
    failurePrefix: 'Failed to apply',
    timeout: timeout,
    detectUnavailableResponse: detectUnavailableResponse,
  );
}

void main() {
  setUpAll(() {
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
      () => bridge.runPrivilegedCommand(
        method: any(named: 'method'),
        args: any(named: 'args'),
        timeout: any(named: 'timeout'),
        detectUnavailableResponse: any(named: 'detectUnavailableResponse'),
      ),
    ).thenAnswer((_) async {});
  }

  void stubThrow(LegionBridgeException error) {
    when(
      () => bridge.runPrivilegedCommand(
        method: any(named: 'method'),
        args: any(named: 'args'),
        timeout: any(named: 'timeout'),
        detectUnavailableResponse: any(named: 'detectUnavailableResponse'),
      ),
    ).thenThrow(error);
  }

  test('forwards method and args to the bridge', () async {
    stubSuccess();

    await repository.run(['set-feature', 'X', '1']);

    verify(
      () => bridge.runPrivilegedCommand(
        method: 'feature.set',
        args: ['set-feature', 'X', '1'],
        timeout: const Duration(seconds: 5),
        detectUnavailableResponse: true,
      ),
    ).called(1);
  });

  test('defaults forwarded match the bridge defaults (5s, true)', () async {
    stubSuccess();

    await repository.run(['a']);

    final captured = verify(
      () => bridge.runPrivilegedCommand(
        method: any(named: 'method'),
        args: any(named: 'args'),
        timeout: captureAny(named: 'timeout'),
        detectUnavailableResponse: captureAny(
          named: 'detectUnavailableResponse',
        ),
      ),
    ).captured;
    expect(captured, [const Duration(seconds: 5), true]);
  });

  test('forwards overridden timeout and detectUnavailableResponse', () async {
    stubSuccess();

    await repository.run(
      ['a'],
      timeout: const Duration(seconds: 10),
      detectUnavailableResponse: false,
    );

    verify(
      () => bridge.runPrivilegedCommand(
        method: any(named: 'method'),
        args: any(named: 'args'),
        timeout: const Duration(seconds: 10),
        detectUnavailableResponse: false,
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
