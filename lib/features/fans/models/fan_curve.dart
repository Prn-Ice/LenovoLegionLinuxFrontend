import 'package:equatable/equatable.dart';

enum FanSpeedUnit { rpm, percent, level, unknown }

enum FanChannel {
  cpu('CPU fan'),
  gpu('GPU fan');

  const FanChannel(this.label);

  final String label;
}

enum FanCurveSchema { full, speedOnly }

enum FanCurveWriteStatus { supported, unvalidated, unsupported, unreadable }

class FanCurvePoint extends Equatable {
  const FanCurvePoint({
    this.fan1Rpm,
    this.fan2Rpm,
    this.fan1Level,
    this.fan2Level,
    this.fan1Pwm,
    this.cpuLowerTemp,
    this.cpuUpperTemp,
    this.gpuLowerTemp,
    this.gpuUpperTemp,
    this.icLowerTemp,
    this.icUpperTemp,
    this.accel,
    this.decel,
  });

  final int? fan1Rpm;
  final int? fan2Rpm;
  final int? fan1Level;
  final int? fan2Level;
  final int? fan1Pwm;
  final int? cpuLowerTemp;
  final int? cpuUpperTemp;
  final int? gpuLowerTemp;
  final int? gpuUpperTemp;
  final int? icLowerTemp;
  final int? icUpperTemp;
  final int? accel;
  final int? decel;

  FanCurvePoint copyWith({
    Object? fan1Rpm = _unset,
    Object? fan2Rpm = _unset,
    Object? fan1Level = _unset,
    Object? fan2Level = _unset,
    Object? fan1Pwm = _unset,
    Object? cpuLowerTemp = _unset,
    Object? cpuUpperTemp = _unset,
    Object? gpuLowerTemp = _unset,
    Object? gpuUpperTemp = _unset,
    Object? icLowerTemp = _unset,
    Object? icUpperTemp = _unset,
    Object? accel = _unset,
    Object? decel = _unset,
  }) {
    return FanCurvePoint(
      fan1Rpm: fan1Rpm == _unset ? this.fan1Rpm : fan1Rpm as int?,
      fan2Rpm: fan2Rpm == _unset ? this.fan2Rpm : fan2Rpm as int?,
      fan1Level: fan1Level == _unset ? this.fan1Level : fan1Level as int?,
      fan2Level: fan2Level == _unset ? this.fan2Level : fan2Level as int?,
      fan1Pwm: fan1Pwm == _unset ? this.fan1Pwm : fan1Pwm as int?,
      cpuLowerTemp: cpuLowerTemp == _unset
          ? this.cpuLowerTemp
          : cpuLowerTemp as int?,
      cpuUpperTemp: cpuUpperTemp == _unset
          ? this.cpuUpperTemp
          : cpuUpperTemp as int?,
      gpuLowerTemp: gpuLowerTemp == _unset
          ? this.gpuLowerTemp
          : gpuLowerTemp as int?,
      gpuUpperTemp: gpuUpperTemp == _unset
          ? this.gpuUpperTemp
          : gpuUpperTemp as int?,
      icLowerTemp: icLowerTemp == _unset
          ? this.icLowerTemp
          : icLowerTemp as int?,
      icUpperTemp: icUpperTemp == _unset
          ? this.icUpperTemp
          : icUpperTemp as int?,
      accel: accel == _unset ? this.accel : accel as int?,
      decel: decel == _unset ? this.decel : decel as int?,
    );
  }

  static const _unset = Object();

  @override
  List<Object?> get props => [
    fan1Rpm,
    fan2Rpm,
    fan1Level,
    fan2Level,
    fan1Pwm,
    cpuLowerTemp,
    cpuUpperTemp,
    gpuLowerTemp,
    gpuUpperTemp,
    icLowerTemp,
    icUpperTemp,
    accel,
    decel,
  ];
}

class FanCurve extends Equatable {
  const FanCurve({
    required this.name,
    required this.points,
    this.enableMiniFanCurve = true,
    this.fan1MaxRpm,
    this.fan2MaxRpm,
    this.speedUnit = FanSpeedUnit.rpm,
    this.schema = FanCurveSchema.full,
    this.writeStatus = FanCurveWriteStatus.supported,
    this.activePointCount,
    this.fan1LevelRpmTable,
    this.fan2LevelRpmTable,
  });

  final String name;
  final List<FanCurvePoint> points;
  final bool enableMiniFanCurve;
  final int? fan1MaxRpm;
  final int? fan2MaxRpm;
  final FanSpeedUnit speedUnit;
  final FanCurveSchema schema;
  final FanCurveWriteStatus writeStatus;
  final int? activePointCount;
  final List<int>? fan1LevelRpmTable;
  final List<int>? fan2LevelRpmTable;

  bool get canEdit =>
      schema == FanCurveSchema.full &&
      writeStatus == FanCurveWriteStatus.supported;

  /// Compares the fields the sysfs backend can preserve. Fan RPMs are
  /// normalised through the PWM byte because the backend quantises them.
  bool matchesReadback(FanCurve other) {
    if (schema != other.schema ||
        speedUnit != other.speedUnit ||
        points.isEmpty ||
        points.length != other.points.length ||
        fan1MaxRpm != other.fan1MaxRpm ||
        fan2MaxRpm != other.fan2MaxRpm) {
      return false;
    }
    for (var i = 0; i < points.length; i++) {
      final expected = points[i];
      final actual = other.points[i];
      if (schema == FanCurveSchema.speedOnly) {
        if (expected.fan1Pwm == null || expected.fan1Pwm != actual.fan1Pwm) {
          return false;
        }
        continue;
      }
      if (expected.fan1Rpm == null ||
          expected.fan2Rpm == null ||
          actual.fan1Rpm == null ||
          actual.fan2Rpm == null ||
          fan1MaxRpm == null ||
          fan1MaxRpm! <= 0 ||
          fan2MaxRpm == null ||
          fan2MaxRpm! <= 0) {
        return false;
      }
      if (expected.cpuLowerTemp != actual.cpuLowerTemp ||
          expected.cpuUpperTemp != actual.cpuUpperTemp ||
          expected.gpuLowerTemp != actual.gpuLowerTemp ||
          expected.gpuUpperTemp != actual.gpuUpperTemp ||
          expected.icLowerTemp != actual.icLowerTemp ||
          expected.icUpperTemp != actual.icUpperTemp ||
          expected.accel != actual.accel ||
          expected.decel != actual.decel ||
          _pwm(expected.fan1Rpm, fan1MaxRpm) !=
              _pwm(actual.fan1Rpm, other.fan1MaxRpm) ||
          _pwm(expected.fan2Rpm, fan2MaxRpm) !=
              _pwm(actual.fan2Rpm, other.fan2MaxRpm)) {
        return false;
      }
    }
    return true;
  }

  static int? _pwm(int? rpm, int? maximum) {
    if (rpm == null || maximum == null || maximum <= 0) return null;
    return (rpm / maximum * 255).round().clamp(0, 255);
  }

  FanCurve copyWithPoint(int index, FanCurvePoint point) {
    final updated = List<FanCurvePoint>.from(points);
    updated[index] = point;
    return FanCurve(
      name: name,
      points: List.unmodifiable(updated),
      enableMiniFanCurve: enableMiniFanCurve,
      fan1MaxRpm: fan1MaxRpm,
      fan2MaxRpm: fan2MaxRpm,
      speedUnit: speedUnit,
      schema: schema,
      writeStatus: writeStatus,
      activePointCount: activePointCount,
      fan1LevelRpmTable: fan1LevelRpmTable,
      fan2LevelRpmTable: fan2LevelRpmTable,
    );
  }

  FanCurve copyWith({
    String? name,
    List<FanCurvePoint>? points,
    bool? enableMiniFanCurve,
    int? fan1MaxRpm,
    int? fan2MaxRpm,
    FanSpeedUnit? speedUnit,
    FanCurveSchema? schema,
    FanCurveWriteStatus? writeStatus,
    int? activePointCount,
    List<int>? fan1LevelRpmTable,
    List<int>? fan2LevelRpmTable,
  }) {
    return FanCurve(
      name: name ?? this.name,
      points: points ?? this.points,
      enableMiniFanCurve: enableMiniFanCurve ?? this.enableMiniFanCurve,
      fan1MaxRpm: fan1MaxRpm ?? this.fan1MaxRpm,
      fan2MaxRpm: fan2MaxRpm ?? this.fan2MaxRpm,
      speedUnit: speedUnit ?? this.speedUnit,
      schema: schema ?? this.schema,
      writeStatus: writeStatus ?? this.writeStatus,
      activePointCount: activePointCount ?? this.activePointCount,
      fan1LevelRpmTable: fan1LevelRpmTable ?? this.fan1LevelRpmTable,
      fan2LevelRpmTable: fan2LevelRpmTable ?? this.fan2LevelRpmTable,
    );
  }

  String toYaml() {
    if (schema != FanCurveSchema.full ||
        points.isEmpty ||
        points.any(
          (p) =>
              p.fan1Rpm == null ||
              p.fan2Rpm == null ||
              p.cpuLowerTemp == null ||
              p.cpuUpperTemp == null ||
              p.gpuLowerTemp == null ||
              p.gpuUpperTemp == null ||
              p.icLowerTemp == null ||
              p.icUpperTemp == null ||
              p.accel == null ||
              p.decel == null,
        )) {
      throw StateError(
        'Fan curve does not contain a complete writable schema.',
      );
    }
    final buf = StringBuffer();
    buf.writeln('name: $name');
    buf.writeln('entries:');
    for (final p in points) {
      buf.writeln('- fan1_speed: ${p.fan1Rpm}.0');
      buf.writeln('  fan2_speed: ${p.fan2Rpm}.0');
      buf.writeln('  cpu_lower_temp: ${p.cpuLowerTemp}');
      buf.writeln('  cpu_upper_temp: ${p.cpuUpperTemp}');
      buf.writeln('  gpu_lower_temp: ${p.gpuLowerTemp}');
      buf.writeln('  gpu_upper_temp: ${p.gpuUpperTemp}');
      buf.writeln('  ic_lower_temp: ${p.icLowerTemp}');
      buf.writeln('  ic_upper_temp: ${p.icUpperTemp}');
      buf.writeln('  acceleration: ${p.accel}');
      buf.writeln('  deceleration: ${p.decel}');
    }
    buf.writeln(
      'enable_minifancurve: ${enableMiniFanCurve ? 'true' : 'false'}',
    );
    return buf.toString();
  }

  @override
  List<Object?> get props => [
    name,
    points,
    enableMiniFanCurve,
    fan1MaxRpm,
    fan2MaxRpm,
    speedUnit,
    schema,
    writeStatus,
    activePointCount,
    fan1LevelRpmTable,
    fan2LevelRpmTable,
  ];
}

/// Returns the curve point whose [channel] fan speed is closest to [rpm].
///
/// The step number a user sees is this index plus one. Returns null when the
/// live speed is unknown or the curve stores no speed for [channel].
int? nearestStepIndex(FanCurve curve, FanChannel channel, int? rpm) {
  if (rpm == null) return null;
  int? nearestIndex;
  var nearestDistance = 0;
  for (var index = 0; index < curve.points.length; index++) {
    final pointRpm = channel == FanChannel.cpu
        ? curve.points[index].fan1Rpm
        : curve.points[index].fan2Rpm;
    if (pointRpm == null) continue;
    final distance = (pointRpm - rpm).abs();
    if (nearestIndex == null || distance < nearestDistance) {
      nearestIndex = index;
      nearestDistance = distance;
    }
  }
  return nearestIndex;
}
