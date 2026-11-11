import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../core/models/app_failure.dart';
import '../../../core/models/control_mode.dart';
import '../models/service_control.dart';

class SettingsState extends Equatable {
  const SettingsState({
    required this.services,
    required this.isLoading,
    required this.isApplying,
    required this.errorMessage,
    required this.noticeMessage,
    required this.themeMode,
    required this.yaruVariant,
    this.accentFollowsPowerMode = false,
    this.appearanceErrorMessage,
    this.activeControlMode = ControlMode.installedService,
    this.nextControlMode = ControlMode.installedService,
    this.isSavingControlMode = false,
    this.controlModeErrorMessage,
  });

  factory SettingsState.initial() => const SettingsState(
    services: [],
    isLoading: false,
    isApplying: false,
    errorMessage: null,
    noticeMessage: null,
    themeMode: ThemeMode.system,
    yaruVariant: null,
  );

  static const _unset = Object();

  final ControlMode activeControlMode;
  final ControlMode nextControlMode;
  final bool isSavingControlMode;
  final AppFailure? controlModeErrorMessage;
  final List<ServiceControl> services;
  final bool isLoading;
  final bool isApplying;
  final AppFailure? errorMessage;
  final String? noticeMessage;
  final ThemeMode themeMode;
  final YaruVariant? yaruVariant;
  final bool accentFollowsPowerMode;
  final String? appearanceErrorMessage;

  bool get hasLoaded => services.isNotEmpty;

  SettingsState copyWith({
    List<ServiceControl>? services,
    bool? isLoading,
    bool? isApplying,
    Object? errorMessage = _unset,
    Object? noticeMessage = _unset,
    ThemeMode? themeMode,
    Object? yaruVariant = _unset,
    bool? accentFollowsPowerMode,
    Object? appearanceErrorMessage = _unset,
    ControlMode? activeControlMode,
    ControlMode? nextControlMode,
    bool? isSavingControlMode,
    Object? controlModeErrorMessage = _unset,
  }) {
    return SettingsState(
      activeControlMode: activeControlMode ?? this.activeControlMode,
      nextControlMode: nextControlMode ?? this.nextControlMode,
      isSavingControlMode: isSavingControlMode ?? this.isSavingControlMode,
      controlModeErrorMessage: controlModeErrorMessage == _unset
          ? this.controlModeErrorMessage
          : AppFailure.optional(controlModeErrorMessage),
      services: services ?? this.services,
      isLoading: isLoading ?? this.isLoading,
      isApplying: isApplying ?? this.isApplying,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : AppFailure.optional(errorMessage),
      noticeMessage: noticeMessage == _unset
          ? this.noticeMessage
          : noticeMessage as String?,
      themeMode: themeMode ?? this.themeMode,
      accentFollowsPowerMode:
          accentFollowsPowerMode ?? this.accentFollowsPowerMode,
      appearanceErrorMessage: appearanceErrorMessage == _unset
          ? this.appearanceErrorMessage
          : appearanceErrorMessage as String?,
      yaruVariant: yaruVariant == _unset
          ? this.yaruVariant
          : yaruVariant as YaruVariant?,
    );
  }

  @override
  List<Object?> get props => [
    activeControlMode,
    nextControlMode,
    isSavingControlMode,
    controlModeErrorMessage,
    services,
    isLoading,
    isApplying,
    errorMessage,
    noticeMessage,
    themeMode,
    yaruVariant,
    accentFollowsPowerMode,
    appearanceErrorMessage,
  ];
}
