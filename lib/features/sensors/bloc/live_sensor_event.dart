import 'package:equatable/equatable.dart';

sealed class LiveSensorEvent extends Equatable {
  const LiveSensorEvent();
  @override
  List<Object?> get props => const [];
}

final class LiveSensorStarted extends LiveSensorEvent {
  const LiveSensorStarted();
}

final class LiveSensorTicked extends LiveSensorEvent {
  const LiveSensorTicked();
}
