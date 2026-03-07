class DisplayLightingSnapshot {
  const DisplayLightingSnapshot({
    required this.hybridModeEnabled,
    required this.hybridModeSupported,
    required this.overdriveEnabled,
    required this.overdriveSupported,
    required this.whiteKeyboardBacklightEnabled,
    required this.whiteKeyboardBacklightSupported,
    required this.yLogoLightEnabled,
    required this.yLogoLightSupported,
    required this.ioPortLightEnabled,
    required this.ioPortLightSupported,
    required this.xrandrOutputName,
    required this.availableRefreshRates,
    required this.currentRefreshRate,
  });

  final bool? hybridModeEnabled;
  final bool hybridModeSupported;
  final bool? overdriveEnabled;
  final bool overdriveSupported;
  final bool? whiteKeyboardBacklightEnabled;
  final bool whiteKeyboardBacklightSupported;
  final bool? yLogoLightEnabled;
  final bool yLogoLightSupported;
  final bool? ioPortLightEnabled;
  final bool ioPortLightSupported;
  final String? xrandrOutputName;
  final List<double>? availableRefreshRates;
  final double? currentRefreshRate;
}
