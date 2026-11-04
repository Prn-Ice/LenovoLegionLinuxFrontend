import 'package:equatable/equatable.dart';

import '../../../core/models/control_selectors.dart';

class ServiceControl extends Equatable {
  const ServiceControl({
    required this.service,
    required this.label,
    required this.units,
    required this.supported,
    required this.active,
    required this.enabled,
  });

  final ControlService service;
  final String label;
  final List<String> units;
  final bool supported;
  final bool active;
  final bool enabled;

  bool get targetEnabled => supported && enabled;

  ServiceControl copyWith({bool? supported, bool? active, bool? enabled}) {
    return ServiceControl(
      service: service,
      label: label,
      units: units,
      supported: supported ?? this.supported,
      active: active ?? this.active,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  List<Object?> get props => [service, label, units, supported, active, enabled];
}
