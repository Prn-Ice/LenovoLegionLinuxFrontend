import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/automation/bloc/automation_state.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';

void main() {
  group('AutomationState.initial', () {
    test('isLoading and isExecuting are false', () {
      final s = AutomationState.initial();
      expect(s.isLoading, isFalse);
      expect(s.isExecuting, isFalse);
    });

    test('currentSnapshot and lastRunAt are null', () {
      final s = AutomationState.initial();
      expect(s.currentSnapshot, isNull);
      expect(s.lastRunAt, isNull);
    });

    test('config is defaults', () {
      expect(
        AutomationState.initial().config,
        equals(AutomationConfig.defaults()),
      );
    });
  });

  group('AutomationState.isRunnerActive', () {
    test('false when config.runnerEnabled is false', () {
      expect(AutomationState.initial().isRunnerActive, isFalse);
    });

    test('true when config.runnerEnabled is true', () {
      final s = AutomationState.initial().copyWith(
        config: AutomationConfig.defaults().copyWith(runnerEnabled: true),
      );
      expect(s.isRunnerActive, isTrue);
    });
  });

  group('AutomationState.copyWith sentinel', () {
    test('copyWith with no args returns equal state', () {
      expect(
        AutomationState.initial().copyWith(),
        equals(AutomationState.initial()),
      );
    });

    test('copyWith(errorMessage: null) clears it', () {
      final s = AutomationState.initial().copyWith(errorMessage: 'bad').copyWith(
        errorMessage: null,
      );
      expect(s.errorMessage, isNull);
    });

    test('copyWith omitting errorMessage preserves it', () {
      final s = AutomationState.initial()
          .copyWith(errorMessage: 'err')
          .copyWith(isLoading: true);
      expect(s.errorMessage, equals('err'));
    });

    test('copyWith(lastRunAt: null) clears DateTime', () {
      final now = DateTime.now();
      final s = AutomationState.initial()
          .copyWith(lastRunAt: now)
          .copyWith(lastRunAt: null);
      expect(s.lastRunAt, isNull);
    });
  });

  group('AutomationState props', () {
    test('identical initial states are equal', () {
      expect(AutomationState.initial(), equals(AutomationState.initial()));
    });

    test('differ when isExecuting differs', () {
      final a = AutomationState.initial();
      final b = a.copyWith(isExecuting: true);
      expect(a, isNot(equals(b)));
    });
  });
}
