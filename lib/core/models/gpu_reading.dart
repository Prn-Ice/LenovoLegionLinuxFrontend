import 'package:equatable/equatable.dart';

/// Readings from one GPU. Missing measurements stay null, including usage.
class GpuReading extends Equatable {
  const GpuReading({
    this.name,
    this.usagePercent,
    this.clockGhz,
    this.tempC,
    this.fanPercent,
    this.vramUsedGb,
    this.vramTotalGb,
    this.powerDrawW,
    this.performanceState,
  });

  final String? name;
  final double? usagePercent;
  final double? clockGhz;
  final double? tempC;
  final int? fanPercent;
  final double? vramUsedGb;
  final double? vramTotalGb;
  final double? powerDrawW;
  final String? performanceState;

  @override
  List<Object?> get props => [
    name,
    usagePercent,
    clockGhz,
    tempC,
    fanPercent,
    vramUsedGb,
    vramTotalGb,
    powerDrawW,
    performanceState,
  ];
}
