import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/fan_icon.dart';

enum AppSection {
  dashboard,
  power,
  fans,
  battery,
  lighting,
  dgpu,
  automation,
  settings,
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
      case AppSection.dgpu:
        return 'Discrete GPU';
      case AppSection.lighting:
        return 'Lighting';
      case AppSection.automation:
        return 'Automation';
      case AppSection.settings:
        return 'Settings';
    }
  }

  Widget get icon {
    switch (this) {
      case AppSection.dashboard:
        return const Icon(YaruIcons.app_grid, size: 20);
      case AppSection.power:
        return const Icon(YaruIcons.shutdown, size: 20);
      case AppSection.fans:
        return const FanIcon();
      case AppSection.battery:
        return const Icon(YaruIcons.battery, size: 20);
      case AppSection.dgpu:
        return const Icon(YaruIcons.chip, size: 20);
      case AppSection.lighting:
        return const Icon(YaruIcons.keyboard, size: 20);
      case AppSection.automation:
        return const Icon(YaruIcons.media_play, size: 20);
      case AppSection.settings:
        return const Icon(YaruIcons.gear, size: 20);
    }
  }
}
