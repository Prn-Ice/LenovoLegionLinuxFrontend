import 'package:equatable/equatable.dart';

import '../../../core/models/control_selectors.dart';

class PowerLimitSpec extends Equatable {
  const PowerLimitSpec({
    required this.id,
    required this.label,
    this.feature,
    required this.sysfsAttribute,
    this.unit = 'W',
    required this.min,
    required this.max,
  });

  final String id;
  final String label;
  final ControlFeature? feature;
  final String sysfsAttribute;
  final String unit;
  final int min;
  final int max;

  /// The lower bound accepted for requests by the app.
  ///
  /// This is separate from the values the hardware reports. A device can
  /// truthfully report zero or a value above this app input bound.
  int get effectiveMin => min > 0 ? min : 1;

  bool get isWritable => feature != null;

  @override
  List<Object?> get props => [
    id,
    label,
    feature,
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
    this.reference,
  });

  final PowerLimitSpec spec;
  final int value;
  final int? reference;

  @override
  List<Object?> get props => [spec, value, reference];
}
