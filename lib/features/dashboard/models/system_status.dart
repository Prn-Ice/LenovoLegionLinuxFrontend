import 'package:equatable/equatable.dart';

class SystemStatus extends Equatable {
  const SystemStatus({required this.updatedAt, this.powerProfile, this.error});

  factory SystemStatus.initial() => SystemStatus(updatedAt: DateTime.now());

  final DateTime updatedAt;
  final String? powerProfile;
  final String? error;

  bool get hasError => error != null && error!.isNotEmpty;

  String get powerProfileLabel {
    final value = powerProfile?.trim();
    return value == null || value.isEmpty ? 'Unavailable' : value;
  }

  @override
  List<Object?> get props => [updatedAt, powerProfile, error];
}
