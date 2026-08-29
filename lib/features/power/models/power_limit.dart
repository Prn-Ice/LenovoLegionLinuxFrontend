import 'package:equatable/equatable.dart';

class PowerLimitSpec extends Equatable {
  const PowerLimitSpec({
    required this.id,
    required this.label,
    required this.featureName,
    required this.sysfsAttribute,
    required this.min,
    required this.max,
  });

  final String id;
  final String label;
  final String featureName;
  final String sysfsAttribute;
  final int min;
  final int max;

  @override
  List<Object?> get props => [id, label, featureName, sysfsAttribute, min, max];
}

class PowerLimitReading extends Equatable {
  const PowerLimitReading({required this.spec, required this.value});

  final PowerLimitSpec spec;
  final int value;

  @override
  List<Object?> get props => [spec, value];
}
