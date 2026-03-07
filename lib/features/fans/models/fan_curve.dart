import 'package:equatable/equatable.dart';

class FanCurvePoint extends Equatable {
  const FanCurvePoint({
    required this.fan1Rpm,
    required this.fan2Rpm,
    required this.cpuLowerTemp,
    required this.cpuUpperTemp,
    required this.gpuLowerTemp,
    required this.gpuUpperTemp,
    required this.icLowerTemp,
    required this.icUpperTemp,
    required this.accel,
    required this.decel,
  });

  final int fan1Rpm;
  final int fan2Rpm;
  final int cpuLowerTemp;
  final int cpuUpperTemp;
  final int gpuLowerTemp;
  final int gpuUpperTemp;
  final int icLowerTemp;
  final int icUpperTemp;
  final int accel;
  final int decel;

  FanCurvePoint copyWith({
    int? fan1Rpm,
    int? fan2Rpm,
    int? cpuLowerTemp,
    int? cpuUpperTemp,
    int? gpuLowerTemp,
    int? gpuUpperTemp,
    int? icLowerTemp,
    int? icUpperTemp,
    int? accel,
    int? decel,
  }) {
    return FanCurvePoint(
      fan1Rpm: fan1Rpm ?? this.fan1Rpm,
      fan2Rpm: fan2Rpm ?? this.fan2Rpm,
      cpuLowerTemp: cpuLowerTemp ?? this.cpuLowerTemp,
      cpuUpperTemp: cpuUpperTemp ?? this.cpuUpperTemp,
      gpuLowerTemp: gpuLowerTemp ?? this.gpuLowerTemp,
      gpuUpperTemp: gpuUpperTemp ?? this.gpuUpperTemp,
      icLowerTemp: icLowerTemp ?? this.icLowerTemp,
      icUpperTemp: icUpperTemp ?? this.icUpperTemp,
      accel: accel ?? this.accel,
      decel: decel ?? this.decel,
    );
  }

  @override
  List<Object?> get props => [
    fan1Rpm,
    fan2Rpm,
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
  });

  final String name;
  final List<FanCurvePoint> points;
  final bool enableMiniFanCurve;

  FanCurve copyWithPoint(int index, FanCurvePoint point) {
    final updated = List<FanCurvePoint>.from(points);
    updated[index] = point;
    return FanCurve(
      name: name,
      points: List.unmodifiable(updated),
      enableMiniFanCurve: enableMiniFanCurve,
    );
  }

  FanCurve copyWith({
    String? name,
    List<FanCurvePoint>? points,
    bool? enableMiniFanCurve,
  }) {
    return FanCurve(
      name: name ?? this.name,
      points: points ?? this.points,
      enableMiniFanCurve: enableMiniFanCurve ?? this.enableMiniFanCurve,
    );
  }

  String toYaml() {
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
    buf.writeln('enable_minifancurve: ${enableMiniFanCurve ? 'true' : 'false'}');
    return buf.toString();
  }

  @override
  List<Object?> get props => [name, points, enableMiniFanCurve];
}
