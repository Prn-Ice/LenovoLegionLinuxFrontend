import 'package:equatable/equatable.dart';

import '../models/about_snapshot.dart';

class AboutState extends Equatable {
  const AboutState({
    required this.snapshot,
    required this.isLoading,
    required this.errorMessage,
  });

  factory AboutState.initial() =>
      const AboutState(snapshot: null, isLoading: false, errorMessage: null);

  static const _unset = Object();

  final AboutSnapshot? snapshot;
  final bool isLoading;
  final String? errorMessage;

  bool get hasLoaded => snapshot != null;

  AboutState copyWith({
    Object? snapshot = _unset,
    bool? isLoading,
    Object? errorMessage = _unset,
  }) {
    return AboutState(
      snapshot: snapshot == _unset ? this.snapshot : snapshot as AboutSnapshot?,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  @override
  List<Object?> get props => [snapshot, isLoading, errorMessage];
}
