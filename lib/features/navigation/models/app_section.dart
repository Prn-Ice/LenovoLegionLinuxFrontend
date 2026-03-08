import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

enum AppSection {
  dashboard,
  power,
  fans,
  battery,
  displayLighting,
  bootLogo,
  dgpu,
  automation,
  settings,
  about,
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
        return 'Battery & Devices';
      case AppSection.displayLighting:
        return 'Display & Lighting';
      case AppSection.bootLogo:
        return 'Boot Logo';
      case AppSection.dgpu:
        return 'Discrete GPU';
      case AppSection.automation:
        return 'Automation';
      case AppSection.settings:
        return 'Settings';
      case AppSection.about:
        return 'About';
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
      case AppSection.displayLighting:
        return Icons.display_settings_outlined;
      case AppSection.bootLogo:
        return Icons.image_outlined;
      case AppSection.dgpu:
        return Icons.memory_outlined;
      case AppSection.automation:
        return Icons.auto_mode_outlined;
      case AppSection.settings:
        return Icons.settings_outlined;
      case AppSection.about:
        return Icons.info_outline;
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
      case AppSection.displayLighting:
        return YaruIcons.display_layout;
      case AppSection.bootLogo:
        return YaruIcons.image;
      case AppSection.dgpu:
        return YaruIcons.chip;
      case AppSection.automation:
        return YaruIcons.gear_dots;
      case AppSection.settings:
        return YaruIcons.gear;
      case AppSection.about:
        return YaruIcons.information;
    }
  }
}
