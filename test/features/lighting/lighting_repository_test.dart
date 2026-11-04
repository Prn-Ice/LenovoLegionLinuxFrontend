import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/services/legion_frontend_bridge_service.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/features/lighting/repository/lighting_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockBridge extends Mock implements LegionFrontendBridgeService {}

class _MockSysfs extends Mock implements LegionSysfsService {}

void main() {
  setUpAll(() {
    registerFallbackValue((LegionControlClient client) async {});
    registerFallbackValue(Duration.zero);
    registerFallbackValue(<String>[]);
  });

  late _MockBridge bridge;
  late LightingRepository repository;

  setUp(() {
    bridge = _MockBridge();
    repository = LightingRepository(
      sysfsService: _MockSysfs(),
      bridgeService: bridge,
    );
  });

  test(
    'setIoPortLight forwards the feature.set command through the base',
    () async {
      when(
        () => bridge.runControlOperation(
          operation: any(named: 'operation'),
          method: any(named: 'method'),
          args: any(named: 'args'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async {});

      await repository.setIoPortLight(true);

      verify(
        () => bridge.runControlOperation(
          operation: any(named: 'operation'),
          method: 'feature.set',
          args: ['IOPortLight', 'true'],
          timeout: const Duration(seconds: 5),
        ),
      ).called(1);
    },
  );

  test(
    'setIoPortLight normalizes the failure message to the base shape',
    () async {
      when(
        () => bridge.runControlOperation(
          operation: any(named: 'operation'),
          method: any(named: 'method'),
          args: any(named: 'args'),
          timeout: any(named: 'timeout'),
        ),
      ).thenThrow(
        const LegionBridgeException(
          code: LegionBridgeErrorCode.commandFailed,
          method: 'feature.set',
          message: 'x',
          stderr: 'boom',
        ),
      );

      await expectLater(
        repository.setIoPortLight(true),
        throwsA(
          isA<LightingRepositoryException>().having(
            (e) => e.toString(),
            'message',
            'Failed to set IO-port light to on: boom',
          ),
        ),
      );
    },
  );
}
