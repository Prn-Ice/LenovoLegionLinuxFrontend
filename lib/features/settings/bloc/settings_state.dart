import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yaru/yaru.dart';

class SettingsState extends Equatable {
  const SettingsState({
    required this.themeMode,
    required this.yaruVariant,
    this.accentFollowsPowerMode = false,
    this.appearanceErrorMessage,
  });

  factory SettingsState.initial() =>
      const SettingsState(themeMode: ThemeMode.system, yaruVariant: null);

  static const _unset = Object();

  final ThemeMode themeMode;
  final YaruVariant? yaruVariant;
  final bool accentFollowsPowerMode;
  final String? appearanceErrorMessage;

  SettingsState copyWith({
    ThemeMode? themeMode,
    Object? yaruVariant = _unset,
    bool? accentFollowsPowerMode,
    Object? appearanceErrorMessage = _unset,
  }) => SettingsState(
    themeMode: themeMode ?? this.themeMode,
    yaruVariant: yaruVariant == _unset
        ? this.yaruVariant
        : yaruVariant as YaruVariant?,
    accentFollowsPowerMode:
        accentFollowsPowerMode ?? this.accentFollowsPowerMode,
    appearanceErrorMessage: appearanceErrorMessage == _unset
        ? this.appearanceErrorMessage
        : appearanceErrorMessage as String?,
  );

  @override
  List<Object?> get props => [
    themeMode,
    yaruVariant,
    accentFollowsPowerMode,
    appearanceErrorMessage,
  ];
}
