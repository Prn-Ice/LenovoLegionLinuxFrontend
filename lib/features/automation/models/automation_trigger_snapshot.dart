import 'package:equatable/equatable.dart';

class AutomationTriggerSnapshot extends Equatable {
  const AutomationTriggerSnapshot({
    required this.platformProfile,
    required this.onPowerSupply,
  });

  final String? platformProfile;
  final bool? onPowerSupply;

  @override
  List<Object?> get props => [platformProfile, onPowerSupply];
}
