import 'package:equatable/equatable.dart';

class PowerProfileDescriptor extends Equatable {
  const PowerProfileDescriptor({
    required this.profile,
    this.cpuDriver,
    this.platformDriver,
  });

  final String profile;
  final String? cpuDriver;
  final String? platformDriver;

  @override
  List<Object?> get props => [profile, cpuDriver, platformDriver];
}

class PowerProfilesDaemonSnapshot extends Equatable {
  const PowerProfilesDaemonSnapshot({
    required this.activeProfile,
    required this.profiles,
    required this.batteryAware,
    required this.version,
    required this.performanceDegraded,
  });

  final String activeProfile;
  final List<PowerProfileDescriptor> profiles;
  final bool? batteryAware;
  final String? version;
  final String? performanceDegraded;

  bool supports(String profile) =>
      profiles.any((descriptor) => descriptor.profile == profile);

  List<String> get cpuDrivers =>
      _uniqueDrivers(profiles.map((descriptor) => descriptor.cpuDriver));

  List<String> get platformDrivers =>
      _uniqueDrivers(profiles.map((descriptor) => descriptor.platformDriver));

  static List<String> _uniqueDrivers(Iterable<String?> values) {
    final result = <String>[];
    for (final value in values) {
      if (value != null && value.isNotEmpty && !result.contains(value)) {
        result.add(value);
      }
    }
    return List.unmodifiable(result);
  }

  @override
  List<Object?> get props => [
    activeProfile,
    profiles,
    batteryAware,
    version,
    performanceDegraded,
  ];
}
