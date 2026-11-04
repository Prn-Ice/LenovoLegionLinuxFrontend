import 'package:equatable/equatable.dart';

import '../../../core/models/app_failure.dart';
import '../models/live_sensor_snapshot.dart';

class LiveSensorState extends Equatable {
  const LiveSensorState({
    required this.snapshot,
    this.isLoading = false,
    this.errorMessage,
  });

  factory LiveSensorState.initial() =>
      LiveSensorState(snapshot: LiveSensorSnapshot.initial(), isLoading: true);

  final LiveSensorSnapshot snapshot;
  final bool isLoading;
  final AppFailure? errorMessage;

  LiveSensorState copyWith({
    LiveSensorSnapshot? snapshot,
    bool? isLoading,
    Object? errorMessage,
  }) {
    return LiveSensorState(
      snapshot: snapshot ?? this.snapshot,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: AppFailure.optional(errorMessage),
    );
  }

  @override
  List<Object?> get props => [snapshot, isLoading, errorMessage];
}
