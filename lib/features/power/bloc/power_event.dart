import 'package:equatable/equatable.dart';

import '../models/power_limit.dart';
import '../models/power_mode.dart';

sealed class PowerEvent extends Equatable {
  const PowerEvent();

  @override
  List<Object?> get props => const [];
}

final class PowerStarted extends PowerEvent {
  const PowerStarted();
}

final class PowerRefreshRequested extends PowerEvent {
  const PowerRefreshRequested();
}

final class PowerModeSetRequested extends PowerEvent {
  const PowerModeSetRequested(this.mode);

  final PowerMode mode;

  @override
  List<Object?> get props => [mode];
}

final class PowerLimitSetRequested extends PowerEvent {
  const PowerLimitSetRequested({required this.limit, required this.value});

  final PowerLimitSpec limit;
  final int value;

  @override
  List<Object?> get props => [limit, value];
}
