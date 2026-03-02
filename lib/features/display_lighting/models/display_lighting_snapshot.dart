class DisplayLightingSnapshot {
  const DisplayLightingSnapshot({
    required this.hybridModeEnabled,
    required this.hybridModeSupported,
    required this.overdriveEnabled,
    required this.overdriveSupported,
  });

  final bool? hybridModeEnabled;
  final bool hybridModeSupported;
  final bool? overdriveEnabled;
  final bool overdriveSupported;
}
