import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/dashboard/bloc/dashboard_state.dart';

void main() {
  group('DashboardState.initial', () {
    test('hasInitialized is false', () {
      expect(DashboardState.initial().hasInitialized, isFalse);
    });

    test('isLoading and isApplying are false', () {
      final s = DashboardState.initial();
      expect(s.isLoading, isFalse);
      expect(s.isApplying, isFalse);
    });

    test('errorMessage and noticeMessage are null', () {
      final s = DashboardState.initial();
      expect(s.errorMessage, isNull);
      expect(s.noticeMessage, isNull);
    });
  });

  group('DashboardState.copyWith sentinel', () {
    test('copyWith with no args returns equal state', () {
      final baseline = DashboardState.initial();
      expect(baseline.copyWith(), equals(baseline));
    });

    test('copyWith(errorMessage: null) clears it', () {
      final s = DashboardState.initial().copyWith(errorMessage: 'fail').copyWith(
        errorMessage: null,
      );
      expect(s.errorMessage, isNull);
    });

    test('copyWith omitting errorMessage preserves it', () {
      final s = DashboardState.initial()
          .copyWith(errorMessage: 'x')
          .copyWith(isLoading: true);
      expect(s.errorMessage, equals('x'));
    });

    test('copyWith(hasInitialized: true) sets it', () {
      final s = DashboardState.initial().copyWith(hasInitialized: true);
      expect(s.hasInitialized, isTrue);
    });
  });

  group('DashboardState props', () {
    test('state equals itself', () {
      final baseline = DashboardState.initial();
      expect(baseline, equals(baseline));
    });

    test('differ when hasInitialized differs', () {
      final a = DashboardState.initial();
      final b = a.copyWith(hasInitialized: true);
      expect(a, isNot(equals(b)));
    });
  });
}
