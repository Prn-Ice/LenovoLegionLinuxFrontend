import 'package:equatable/equatable.dart';

import '../models/automation_config.dart';
import '../models/automation_trigger_snapshot.dart';

class AutomationState extends Equatable {
  const AutomationState({
    required this.config,
    required this.currentSnapshot,
    required this.isLoading,
    required this.isExecuting,
    required this.lastRunAt,
    required this.lastRunSummary,
    required this.errorMessage,
  });

  factory AutomationState.initial() => AutomationState(
    config: AutomationConfig.defaults(),
    currentSnapshot: null,
    isLoading: false,
    isExecuting: false,
    lastRunAt: null,
    lastRunSummary: null,
    errorMessage: null,
  );

  static const _unset = Object();

  final AutomationConfig config;
  final AutomationTriggerSnapshot? currentSnapshot;
  final bool isLoading;
  final bool isExecuting;
  final DateTime? lastRunAt;
  final String? lastRunSummary;
  final String? errorMessage;

  bool get isRunnerActive => config.runnerEnabled;

  AutomationState copyWith({
    AutomationConfig? config,
    Object? currentSnapshot = _unset,
    bool? isLoading,
    bool? isExecuting,
    Object? lastRunAt = _unset,
    Object? lastRunSummary = _unset,
    Object? errorMessage = _unset,
  }) {
    return AutomationState(
      config: config ?? this.config,
      currentSnapshot: currentSnapshot == _unset
          ? this.currentSnapshot
          : currentSnapshot as AutomationTriggerSnapshot?,
      isLoading: isLoading ?? this.isLoading,
      isExecuting: isExecuting ?? this.isExecuting,
      lastRunAt: lastRunAt == _unset ? this.lastRunAt : lastRunAt as DateTime?,
      lastRunSummary: lastRunSummary == _unset
          ? this.lastRunSummary
          : lastRunSummary as String?,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  @override
  List<Object?> get props => [
    config,
    currentSnapshot,
    isLoading,
    isExecuting,
    lastRunAt,
    lastRunSummary,
    errorMessage,
  ];
}
