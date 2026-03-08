// lib/features/analytics/bloc/analytics_event.dart
import 'package:equatable/equatable.dart';

import 'analytics_state.dart';

sealed class AnalyticsEvent extends Equatable {
  const AnalyticsEvent();

  @override
  List<Object?> get props => const [];
}

final class AnalyticsStarted extends AnalyticsEvent {
  const AnalyticsStarted();
}

final class AnalyticsTicked extends AnalyticsEvent {
  const AnalyticsTicked();
}

/// Change the displayed time window on the graph.
final class AnalyticsWindowChanged extends AnalyticsEvent {
  const AnalyticsWindowChanged(this.window);

  final AnalyticsTimeWindow window;

  @override
  List<Object?> get props => [window];
}
