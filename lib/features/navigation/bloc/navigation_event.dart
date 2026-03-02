import 'package:equatable/equatable.dart';

import '../models/app_section.dart';

sealed class NavigationEvent extends Equatable {
  const NavigationEvent();

  @override
  List<Object?> get props => const [];
}

final class NavigationSectionSelected extends NavigationEvent {
  const NavigationSectionSelected(this.section);

  final AppSection section;

  @override
  List<Object?> get props => [section];
}
