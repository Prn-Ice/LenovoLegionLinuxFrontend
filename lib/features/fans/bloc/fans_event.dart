import 'package:equatable/equatable.dart';

import '../models/fan_curve.dart';

sealed class FansEvent extends Equatable {
  const FansEvent();

  @override
  List<Object?> get props => const [];
}

final class FansStarted extends FansEvent {
  const FansStarted();
}

final class FansRefreshRequested extends FansEvent {
  const FansRefreshRequested();
}

final class FansPresetSelectionChanged extends FansEvent {
  const FansPresetSelectionChanged(this.preset);

  final String preset;

  @override
  List<Object?> get props => [preset];
}

final class FansApplyCurrentPresetRequested extends FansEvent {
  const FansApplyCurrentPresetRequested();
}

final class FansApplySelectedPresetRequested extends FansEvent {
  const FansApplySelectedPresetRequested();
}

final class MiniFanCurveSetRequested extends FansEvent {
  const MiniFanCurveSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class LockFanControllerSetRequested extends FansEvent {
  const LockFanControllerSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class MaximumFanSpeedSetRequested extends FansEvent {
  const MaximumFanSpeedSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class FanCurvePointUpdated extends FansEvent {
  const FanCurvePointUpdated({required this.index, required this.point});

  final int index;
  final FanCurvePoint point;

  @override
  List<Object?> get props => [index, point];
}

final class FanCurveSaveRequested extends FansEvent {
  const FanCurveSaveRequested();
}
