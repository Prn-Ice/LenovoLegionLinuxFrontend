/// Identifies which Settings-owned feature snapshots can be refreshed safely.
class SettingsRefreshTargets {
  const SettingsRefreshTargets({
    required this.bootLogo,
    required this.about,
    required this.devices,
    required this.display,
  });

  factory SettingsRefreshTargets.fromBusyStates({
    required bool bootLogoLoading,
    required bool bootLogoApplying,
    required bool aboutLoading,
    required bool devicesLoading,
    required bool devicesApplying,
    required bool displayLoading,
    required bool displayApplying,
  }) => SettingsRefreshTargets(
    bootLogo: !bootLogoLoading && !bootLogoApplying,
    about: !aboutLoading,
    devices: !devicesLoading && !devicesApplying,
    display: !displayLoading && !displayApplying,
  );

  final bool bootLogo;
  final bool about;
  final bool devices;
  final bool display;

  bool get canRefresh => bootLogo || about || devices || display;
}
