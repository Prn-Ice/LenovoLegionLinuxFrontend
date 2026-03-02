import 'package:equatable/equatable.dart';

import '../models/dashboard_snapshot.dart';

class DashboardState extends Equatable {
  const DashboardState({
    required this.snapshot,
    required this.isLoading,
    required this.isApplying,
    required this.hasInitialized,
    required this.errorMessage,
    required this.noticeMessage,
  });

  factory DashboardState.initial() => DashboardState(
    snapshot: DashboardSnapshot.initial(),
    isLoading: false,
    isApplying: false,
    hasInitialized: false,
    errorMessage: null,
    noticeMessage: null,
  );

  static const _unset = Object();

  final DashboardSnapshot snapshot;
  final bool isLoading;
  final bool isApplying;
  final bool hasInitialized;
  final String? errorMessage;
  final String? noticeMessage;

  DashboardState copyWith({
    DashboardSnapshot? snapshot,
    bool? isLoading,
    bool? isApplying,
    bool? hasInitialized,
    Object? errorMessage = _unset,
    Object? noticeMessage = _unset,
  }) {
    return DashboardState(
      snapshot: snapshot ?? this.snapshot,
      isLoading: isLoading ?? this.isLoading,
      isApplying: isApplying ?? this.isApplying,
      hasInitialized: hasInitialized ?? this.hasInitialized,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
      noticeMessage: noticeMessage == _unset
          ? this.noticeMessage
          : noticeMessage as String?,
    );
  }

  @override
  List<Object?> get props => [
    snapshot,
    isLoading,
    isApplying,
    hasInitialized,
    errorMessage,
    noticeMessage,
  ];
}
