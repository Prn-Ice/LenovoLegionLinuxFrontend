import 'package:equatable/equatable.dart';
import '../models/live_sensor_snapshot.dart';

class LiveSensorState extends Equatable {
  const LiveSensorState({
    required this.snapshot,
    this.isLoading = false,
    this.errorMessage,
  });

  factory LiveSensorState.initial() => LiveSensorState(
    snapshot: LiveSensorSnapshot.initial(),
    isLoading: false,
  );

  final LiveSensorSnapshot snapshot;
  final bool isLoading;
  final String? errorMessage;

  LiveSensorState copyWith({
    LiveSensorSnapshot? snapshot,
    bool? isLoading,
    String? errorMessage,
  }) {
    return LiveSensorState(
      snapshot: snapshot ?? this.snapshot,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [snapshot, isLoading, errorMessage];
}
