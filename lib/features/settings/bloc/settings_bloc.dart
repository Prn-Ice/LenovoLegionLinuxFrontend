import 'package:riverbloc/riverbloc.dart';

import '../repository/appearance_store.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc({AppearanceStore? appearanceStore})
    : _appearanceStore = appearanceStore,
      super(_initialState(appearanceStore)) {
    // One queue across all appearance fields: every save includes all choices.
    on<AppearanceChanged>(
      _onAppearanceChanged,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
  }

  final AppearanceStore? _appearanceStore;

  static SettingsState _initialState(AppearanceStore? store) {
    try {
      return store?.load() ?? SettingsState.initial();
    } catch (error) {
      return SettingsState.initial().copyWith(
        appearanceErrorMessage:
            'Could not load appearance preferences. System appearance '
            'is being used. Check that your application data is readable, then '
            'restart the app. Technical details: $error',
      );
    }
  }

  Future<void> _onAppearanceChanged(
    AppearanceChanged event,
    Emitter<SettingsState> emit,
  ) async {
    final next = switch (event) {
      ThemeModeChanged() => state.copyWith(themeMode: event.themeMode),
      YaruVariantChanged() => state.copyWith(yaruVariant: event.variant),
      AccentFollowsPowerModeChanged() => state.copyWith(
        accentFollowsPowerMode: event.enabled,
      ),
    };
    emit(state.copyWith(appearanceErrorMessage: null));
    try {
      await _appearanceStore?.save(next);
      if (emit.isDone) return;
      emit(next.copyWith(appearanceErrorMessage: null));
    } catch (error) {
      if (emit.isDone) return;
      emit(
        state.copyWith(
          appearanceErrorMessage:
              'Could not save appearance preferences. Your previous appearance '
              'is unchanged. Check free disk space and that your application data '
              'is writable, then try the change again. Technical details: $error',
        ),
      );
    }
  }
}
