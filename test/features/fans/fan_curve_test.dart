import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/fans/models/fan_curve.dart';

FanCurvePoint _makePoint({
  int fan1Rpm = 1000,
  int fan2Rpm = 1000,
  int cpuLower = 40,
  int cpuUpper = 50,
  int gpuLower = 40,
  int gpuUpper = 50,
  int icLower = 40,
  int icUpper = 50,
  int accel = 2,
  int decel = 2,
}) => FanCurvePoint(
  fan1Rpm: fan1Rpm,
  fan2Rpm: fan2Rpm,
  cpuLowerTemp: cpuLower,
  cpuUpperTemp: cpuUpper,
  gpuLowerTemp: gpuLower,
  gpuUpperTemp: gpuUpper,
  icLowerTemp: icLower,
  icUpperTemp: icUpper,
  accel: accel,
  decel: decel,
);

void main() {
  group('FanCurvePoint', () {
    test('copyWith changes only the specified field', () {
      final p = _makePoint(fan1Rpm: 1000, cpuUpper: 50);
      final p2 = p.copyWith(fan1Rpm: 2000);
      expect(p2.fan1Rpm, equals(2000));
      expect(p2.cpuUpperTemp, equals(50));
    });

    test('equality holds for identical instances', () {
      final p1 = _makePoint();
      final p2 = _makePoint();
      expect(p1, equals(p2));
    });
  });

  group('FanCurve', () {
    late List<FanCurvePoint> tenPoints;

    setUp(() {
      tenPoints = List.generate(10, (_) => _makePoint());
    });

    test('has exactly 10 points', () {
      final curve = FanCurve(name: 'test', points: tenPoints);
      expect(curve.points.length, equals(10));
    });

    test('copyWith replaces a point at index', () {
      final curve = FanCurve(name: 'test', points: tenPoints);
      final updated = _makePoint(fan1Rpm: 3000);
      final curve2 = curve.copyWithPoint(2, updated);
      expect(curve2.points[2].fan1Rpm, equals(3000));
      expect(curve2.points[0].fan1Rpm, equals(1000));
    });

    test('toYaml produces parseable output with correct fields', () {
      final curve = FanCurve(
        name: 'custom',
        points: tenPoints,
        enableMiniFanCurve: true,
      );
      final yaml = curve.toYaml();
      expect(yaml, contains('name: custom'));
      expect(yaml, contains('enable_minifancurve: true'));
      expect(yaml, contains('fan1_speed: 1000.0'));
      expect(yaml, contains('cpu_lower_temp: 40'));
      expect(yaml, contains('acceleration: 2'));
    });

    test('toYaml contains exactly 10 entries', () {
      final curve = FanCurve(name: 'custom', points: tenPoints);
      final yaml = curve.toYaml();
      final entryCount = RegExp(r'- fan1_speed').allMatches(yaml).length;
      expect(entryCount, equals(10));
    });
  });
}
