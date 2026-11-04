import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:yaru/yaru.dart';

import '../bloc/settings_state.dart';

/// Primitive, named values remain readable when enum order or defaults change.
class AppearanceStore {
  AppearanceStore(this._box);

  final Box<dynamic> _box;
  static const key = 'appearance';

  SettingsState load() {
    final raw = _box.get(key);
    if (raw is! Map) return SettingsState.initial();
    final theme = ThemeMode.values.where((v) => v.name == raw['themeMode']);
    final variant = YaruVariant.values.where(
      (v) => v.name == raw['yaruVariant'],
    );
    return SettingsState.initial().copyWith(
      themeMode: theme.firstOrNull ?? ThemeMode.system,
      yaruVariant: variant.firstOrNull,
      accentFollowsPowerMode: raw['accentFollowsPowerMode'] == true,
    );
  }

  Future<void> save(SettingsState state) => _box.put(key, {
    'themeMode': state.themeMode.name,
    'yaruVariant': state.yaruVariant?.name,
    'accentFollowsPowerMode': state.accentFollowsPowerMode,
  });
}
