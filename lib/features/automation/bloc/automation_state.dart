import 'package:equatable/equatable.dart';
import '../../../core/models/app_failure.dart';
import '../models/automation_config.dart';

class AutomationState extends Equatable {
  const AutomationState({
    required this.config,
    this.hasLoaded = false,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
  });

  factory AutomationState.initial() =>
      AutomationState(config: AutomationConfig.defaults());

  final AutomationConfig config;
  final bool hasLoaded;
  final bool isLoading;
  final bool isSaving;
  final AppFailure? errorMessage;

  AutomationState copyWith({
    AutomationConfig? config,
    bool? hasLoaded,
    bool? isLoading,
    bool? isSaving,
    Object? errorMessage,
  }) => AutomationState(
    config: config ?? this.config,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    isLoading: isLoading ?? this.isLoading,
    isSaving: isSaving ?? this.isSaving,
    errorMessage: AppFailure.optional(errorMessage),
  );

  @override
  List<Object?> get props => [
    config,
    hasLoaded,
    isLoading,
    isSaving,
    errorMessage,
  ];
}
