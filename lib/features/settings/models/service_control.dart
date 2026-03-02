import 'package:equatable/equatable.dart';

class ServiceControl extends Equatable {
  const ServiceControl({
    required this.id,
    required this.label,
    required this.units,
    required this.supported,
    required this.active,
    required this.enabled,
  });

  final String id;
  final String label;
  final List<String> units;
  final bool supported;
  final bool active;
  final bool enabled;

  bool get targetEnabled => supported && enabled;

  ServiceControl copyWith({bool? supported, bool? active, bool? enabled}) {
    return ServiceControl(
      id: id,
      label: label,
      units: units,
      supported: supported ?? this.supported,
      active: active ?? this.active,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  List<Object?> get props => [id, label, units, supported, active, enabled];
}
