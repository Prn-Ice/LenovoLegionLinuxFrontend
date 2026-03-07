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
}
