import 'package:equatable/equatable.dart';

import '../models/app_section.dart';

class NavigationState extends Equatable {
  const NavigationState({required this.section});

  factory NavigationState.initial() =>
      const NavigationState(section: AppSection.dashboard);

  final AppSection section;

  NavigationState copyWith({AppSection? section}) {
    return NavigationState(section: section ?? this.section);
  }

  @override
  List<Object?> get props => [section];
}
