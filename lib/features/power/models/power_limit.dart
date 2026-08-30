import 'package:equatable/equatable.dart';

class PowerLimitSpec extends Equatable {
  const PowerLimitSpec({
    required this.id,
    required this.label,
    required this.featureName,
    required this.sysfsAttribute,
    this.unit = 'W',
    required this.min,
    required this.max,
  });

  final String id;
  final String label;
  final String featureName;
  final String sysfsAttribute;
  final String unit;
  final int min;
  final int max;

  int get effectiveMin => min > 0 ? min : 1;

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
  const PowerLimitReading({required this.spec, required this.value});

  final PowerLimitSpec spec;
  final int value;

  @override
  List<Object?> get props => [spec, value];
}
