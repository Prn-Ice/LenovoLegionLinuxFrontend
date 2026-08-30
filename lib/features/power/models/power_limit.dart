import 'package:equatable/equatable.dart';

class PowerLimitSpec extends Equatable {
  const PowerLimitSpec({
    required this.id,
    required this.label,
    this.featureName,
    required this.sysfsAttribute,
    this.unit = 'W',
    required this.min,
    required this.max,
  });

  final String id;
  final String label;
  final String? featureName;
  final String sysfsAttribute;
  final String unit;
  final int min;
  final int max;

  int get effectiveMin => min > 0 ? min : 1;

  bool get isWritable => featureName != null;

  @override
  List<Object?> get props => [
    id,
    label,
    featureName,
    sysfsAttribute,
    unit,
    min,
    max,
  ];
}

class PowerLimitReading extends Equatable {
  const PowerLimitReading({
    required this.spec,
    required this.value,
    this.hardwareDefault,
  });

  final PowerLimitSpec spec;
  final int value;
  final int? hardwareDefault;

  @override
  List<Object?> get props => [spec, value, hardwareDefault];
}
