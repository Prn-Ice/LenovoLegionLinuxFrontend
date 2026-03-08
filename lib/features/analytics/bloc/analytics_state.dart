// lib/features/analytics/bloc/analytics_state.dart
import 'package:equatable/equatable.dart';

import '../models/sensor_record.dart';

enum AnalyticsTimeWindow { lastHour, last6h, last24h, last7d, last30d }

extension AnalyticsTimeWindowX on AnalyticsTimeWindow {
  Duration get duration => switch (this) {
    AnalyticsTimeWindow.lastHour => const Duration(hours: 1),
    AnalyticsTimeWindow.last6h => const Duration(hours: 6),
    AnalyticsTimeWindow.last24h => const Duration(hours: 24),
    AnalyticsTimeWindow.last7d => const Duration(days: 7),
    AnalyticsTimeWindow.last30d => const Duration(days: 30),
  };

  String get label => switch (this) {
    AnalyticsTimeWindow.lastHour => '1h',
    AnalyticsTimeWindow.last6h => '6h',
    AnalyticsTimeWindow.last24h => '24h',
    AnalyticsTimeWindow.last7d => '7d',
    AnalyticsTimeWindow.last30d => '30d',
  };
}

class AnalyticsState extends Equatable {
  const AnalyticsState({
    required this.history,
    required this.window,
    required this.errorMessage,
  });

  factory AnalyticsState.initial() => const AnalyticsState(
    history: [],
    window: AnalyticsTimeWindow.lastHour,
    errorMessage: null,
  );

  final List<SensorRecord> history;
  final AnalyticsTimeWindow window;
  final String? errorMessage;

  SensorRecord? get latest => history.isEmpty ? null : history.last;

  AnalyticsState copyWith({
    List<SensorRecord>? history,
    AnalyticsTimeWindow? window,
    Object? errorMessage = _unset,
  }) => AnalyticsState(
    history: history ?? this.history,
    window: window ?? this.window,
    errorMessage: errorMessage == _unset
        ? this.errorMessage
        : errorMessage as String?,
  );

  static const _unset = Object();

  @override
  List<Object?> get props => [history, window, errorMessage];
}
