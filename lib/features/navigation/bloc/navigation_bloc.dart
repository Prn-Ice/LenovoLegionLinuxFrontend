import 'package:riverbloc/riverbloc.dart';

import 'navigation_event.dart';
import 'navigation_state.dart';

class NavigationBloc extends Bloc<NavigationEvent, NavigationState> {
  NavigationBloc() : super(NavigationState.initial()) {
    on<NavigationSectionSelected>(_onSectionSelected);
  }

  void _onSectionSelected(
    NavigationSectionSelected event,
    Emitter<NavigationState> emit,
  ) {
    if (event.section == state.section) {
      return;
    }
    emit(state.copyWith(section: event.section));
  }
}
