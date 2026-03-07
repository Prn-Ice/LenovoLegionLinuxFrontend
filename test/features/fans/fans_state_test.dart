import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/fans/bloc/fans_state.dart';
import 'package:legion_frontend/features/fans/models/fan_curve.dart';

FanCurve _curve(String name) => FanCurve(
  name: name,
  points: List.generate(
    10,
    (_) => const FanCurvePoint(
      fan1Rpm: 1200,
      fan2Rpm: 1200,
      cpuLowerTemp: 40,
      cpuUpperTemp: 50,
      gpuLowerTemp: 40,
      gpuUpperTemp: 50,
      icLowerTemp: 40,
      icUpperTemp: 50,
      accel: 5,
      decel: 5,
    ),
  ),
);

void main() {
  group('FansState.initial', () {
    test('all nullable fields are null', () {
      final s = FansState.initial();
      expect(s.platformProfile, isNull);
      expect(s.onPowerSupply, isNull);
      expect(s.recommendedPreset, isNull);
      expect(s.selectedPreset, isNull);
      expect(s.miniFanCurveEnabled, isNull);
      expect(s.lockFanControllerEnabled, isNull);
      expect(s.maximumFanSpeedEnabled, isNull);
      expect(s.fanCurve, isNull);
      expect(s.errorMessage, isNull);
      expect(s.noticeMessage, isNull);
    });

    test('availablePresets is empty', () {
      expect(FansState.initial().availablePresets, isEmpty);
    });

    test('fanCurveDirty is false', () {
      expect(FansState.initial().fanCurveDirty, isFalse);
    });

    test('hasLoaded is false', () {
      expect(FansState.initial().hasLoaded, isFalse);
    });
  });

  group('FansState.hasLoaded', () {
    test('true when platformProfile is set', () {
      final s = FansState.initial().copyWith(platformProfile: 'balanced');
      expect(s.hasLoaded, isTrue);
    });

    test('true when miniFanCurveEnabled is set', () {
      final s = FansState.initial().copyWith(miniFanCurveEnabled: false);
      expect(s.hasLoaded, isTrue);
    });

    test('true when fanCurve is set', () {
      final s = FansState.initial().copyWith(fanCurve: _curve('test'));
      expect(s.hasLoaded, isTrue);
    });

    test('true when availablePresets is non-empty', () {
      final s = FansState.initial().copyWith(availablePresets: ['quiet-ac']);
      expect(s.hasLoaded, isTrue);
    });
  });

  group('FansState.copyWith sentinel (_unset)', () {
    test('copyWith with no args returns equal state', () {
      final s = FansState.initial();
      expect(s.copyWith(), equals(s));
    });

    test('copyWith(platformProfile: null) clears field', () {
      final s = FansState.initial()
          .copyWith(platformProfile: 'balanced')
          .copyWith(platformProfile: null);
      expect(s.platformProfile, isNull);
    });

    test('copyWith omitting platformProfile preserves it', () {
      final s = FansState.initial().copyWith(platformProfile: 'quiet');
      final updated = s.copyWith(isLoading: true);
      expect(updated.platformProfile, equals('quiet'));
    });

    test('copyWith(fanCurve: null) clears fanCurve', () {
      final s = FansState.initial().copyWith(fanCurve: _curve('x')).copyWith(
        fanCurve: null,
      );
      expect(s.fanCurve, isNull);
    });

    test('copyWith omitting fanCurve preserves it', () {
      final curve = _curve('y');
      final s = FansState.initial().copyWith(fanCurve: curve);
      expect(s.copyWith(isLoading: true).fanCurve, equals(curve));
    });

    test('copyWith(errorMessage: null) clears error', () {
      final s = FansState.initial().copyWith(errorMessage: 'oops').copyWith(
        errorMessage: null,
      );
      expect(s.errorMessage, isNull);
    });
  });

  group('FansState.fanCurveDirty', () {
    test('copyWith(fanCurveDirty: true) sets it', () {
      final s = FansState.initial().copyWith(fanCurveDirty: true);
      expect(s.fanCurveDirty, isTrue);
    });

    test('copyWith omitting fanCurveDirty preserves it', () {
      final s = FansState.initial()
          .copyWith(fanCurveDirty: true)
          .copyWith(isLoading: true);
      expect(s.fanCurveDirty, isTrue);
    });
  });

  group('FansState props', () {
    test('identical states are equal', () {
      expect(FansState.initial(), equals(FansState.initial()));
    });

    test('states differ when fanCurveDirty differs', () {
      final a = FansState.initial();
      final b = a.copyWith(fanCurveDirty: true);
      expect(a, isNot(equals(b)));
    });

    test('states differ when fanCurve differs', () {
      final a = FansState.initial().copyWith(fanCurve: _curve('a'));
      final b = FansState.initial().copyWith(fanCurve: _curve('b'));
      expect(a, isNot(equals(b)));
    });
  });
}
