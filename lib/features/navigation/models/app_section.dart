import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

enum AppSection {
  dashboard,
  power,
  fans,
  battery,
  devices,
  dgpu,
  display,
  lighting,
  automation,
  settings,
  diagnostics,
}

extension AppSectionUi on AppSection {
  String get label {
    switch (this) {
      case AppSection.dashboard:
        return 'Dashboard';
      case AppSection.power:
        return 'Power';
      case AppSection.fans:
        return 'Fans';
      case AppSection.battery:
        return 'Battery';
      case AppSection.devices:
        return 'Devices';
      case AppSection.dgpu:
        return 'Discrete GPU';
      case AppSection.display:
        return 'Display';
      case AppSection.lighting:
        return 'Lighting';
      case AppSection.automation:
        return 'Automation';
      case AppSection.settings:
        return 'Settings';
      case AppSection.diagnostics:
        return 'Diagnostics';
    }
  }

  IconData get icon {
    switch (this) {
      case AppSection.dashboard:
        return Icons.dashboard_outlined;
      case AppSection.power:
        return Icons.bolt_outlined;
      case AppSection.fans:
        return Icons.air_outlined;
      case AppSection.battery:
        return Icons.battery_charging_full_outlined;
      case AppSection.devices:
        return Icons.devices_outlined;
      case AppSection.dgpu:
        return Icons.memory_outlined;
      case AppSection.display:
        return Icons.monitor_outlined;
      case AppSection.lighting:
        return Icons.light_mode_outlined;
      case AppSection.automation:
        return Icons.auto_mode_outlined;
      case AppSection.settings:
        return Icons.settings_outlined;
      case AppSection.diagnostics:
        return Icons.analytics_outlined;
    }
  }

  IconData get yaruIcon {
    switch (this) {
      case AppSection.dashboard:
        return YaruIcons.chip;
      case AppSection.power:
        return YaruIcons.thunderbolt;
      case AppSection.fans:
        return YaruIcons.gears;
      case AppSection.battery:
        return YaruIcons.battery_full_charging;
      case AppSection.devices:
        return YaruIcons.keyboard;
      case AppSection.dgpu:
        return YaruIcons.chip;
      case AppSection.display:
        return YaruIcons.display_layout;
      case AppSection.lighting:
        return YaruIcons.color_select;
      case AppSection.automation:
        return YaruIcons.gear_dots;
      case AppSection.settings:
        return YaruIcons.gear;
      case AppSection.diagnostics:
        return YaruIcons.monitor;
    }
  }
}
