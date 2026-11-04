/// Identifies which Settings-owned feature snapshots can be refreshed safely.
class SettingsRefreshTargets {
  const SettingsRefreshTargets({
    required this.settings,
    required this.bootLogo,
    required this.about,
    required this.devices,
    required this.display,
  });

  factory SettingsRefreshTargets.fromBusyStates({
    required bool settingsLoading,
    required bool settingsApplying,
    required bool bootLogoLoading,
    required bool bootLogoApplying,
    required bool aboutLoading,
    required bool devicesLoading,
    required bool devicesApplying,
    required bool displayLoading,
    required bool displayApplying,
  }) => SettingsRefreshTargets(
    settings: !settingsLoading && !settingsApplying,
    bootLogo: !bootLogoLoading && !bootLogoApplying,
    about: !aboutLoading,
    devices: !devicesLoading && !devicesApplying,
    display: !displayLoading && !displayApplying,
  );

  final bool settings;
  final bool bootLogo;
  final bool about;
  final bool devices;
  final bool display;

  bool get canRefresh => settings || bootLogo || about || devices || display;
}
