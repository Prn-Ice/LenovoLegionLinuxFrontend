import 'package:equatable/equatable.dart';

class DisplaySnapshot extends Equatable {
  const DisplaySnapshot({
    required this.overdriveEnabled,
    required this.overdriveSupported,
    required this.xrandrOutputName,
    required this.availableRefreshRates,
    required this.currentRefreshRate,
  });

  final bool? overdriveEnabled;
  final bool overdriveSupported;
  final String? xrandrOutputName;
  final List<double>? availableRefreshRates;
  final double? currentRefreshRate;

  @override
  List<Object?> get props => [
    overdriveEnabled,
    overdriveSupported,
    xrandrOutputName,
    availableRefreshRates,
    currentRefreshRate,
  ];
}
