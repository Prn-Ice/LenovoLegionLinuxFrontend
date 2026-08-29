import 'package:equatable/equatable.dart';

class CpuPolicySnapshot extends Equatable {
  const CpuPolicySnapshot({
    this.driver,
    this.pstateStatus,
    this.governor,
    this.energyPerformancePreference,
    this.boostEnabled,
    this.minimumFrequencyKhz,
    this.maximumFrequencyKhz,
  });

  final String? driver;
  final String? pstateStatus;
  final String? governor;
  final String? energyPerformancePreference;
  final bool? boostEnabled;
  final int? minimumFrequencyKhz;
  final int? maximumFrequencyKhz;

  bool get hasData =>
      driver != null ||
      pstateStatus != null ||
      governor != null ||
      energyPerformancePreference != null ||
      boostEnabled != null ||
      minimumFrequencyKhz != null ||
      maximumFrequencyKhz != null;

  @override
  List<Object?> get props => [
    driver,
    pstateStatus,
    governor,
    energyPerformancePreference,
    boostEnabled,
    minimumFrequencyKhz,
    maximumFrequencyKhz,
  ];
}
