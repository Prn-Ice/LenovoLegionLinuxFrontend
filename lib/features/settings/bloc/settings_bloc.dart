import 'package:riverbloc/riverbloc.dart';

import '../../../core/models/app_failure.dart';
import '../models/service_control.dart';
import '../repository/appearance_store.dart';
import '../repository/settings_repository.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc({
    required SettingsRepository repository,
    AppearanceStore? appearanceStore,
  }) : _repository = repository,
       _appearanceStore = appearanceStore,
       super(_initialState(appearanceStore)) {
    on<SettingsStarted>(_onStarted);
    on<SettingsRefreshRequested>(_onRefreshRequested);
    on<SettingsServiceToggled>(_onServiceToggled);
    // One queue across all appearance fields: every save includes all choices.
    on<AppearanceChanged>(
      _onAppearanceChanged,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
  }

  final SettingsRepository _repository;
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

  Future<void> _onStarted(
    SettingsStarted event,
    Emitter<SettingsState> emit,
  ) async {
    await _reload(emit, showLoading: true);
  }

  Future<void> _onRefreshRequested(
    SettingsRefreshRequested event,
    Emitter<SettingsState> emit,
  ) async {
    await _reload(emit, showLoading: true);
  }

  Future<void> _onServiceToggled(
    SettingsServiceToggled event,
    Emitter<SettingsState> emit,
  ) async {
    if (state.isApplying) {
      return;
    }

    final service = _findServiceById(event.serviceId, state.services);
    if (service == null) {
      emit(
        state.copyWith(errorMessage: 'Unknown service "${event.serviceId}".'),
      );
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await _repository.setServiceEnabled(service, event.enabled);
      await _reload(emit, showLoading: false);
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage:
              '${service.label} ${event.enabled ? 'enabled' : 'disabled'}.',
        ),
      );
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: error));
    }
  }

  Future<void> _reload(
    Emitter<SettingsState> emit, {
    required bool showLoading,
  }) async {
    if (showLoading) {
      emit(
        state.copyWith(
          isLoading: true,
          errorMessage: null,
          noticeMessage: null,
        ),
      );
    }

    try {
      final snapshot = await _repository.loadSnapshot();
      emit(
        state.copyWith(
          services: snapshot.services,
          isLoading: false,
          errorMessage: null,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: AppFailure.from(
            error,
            message: 'Failed to load settings: $error',
          ),
        ),
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
      // Preserve service updates that may have completed during the disk write.
      emit(
        state.copyWith(
          themeMode: next.themeMode,
          yaruVariant: next.yaruVariant,
          accentFollowsPowerMode: next.accentFollowsPowerMode,
          appearanceErrorMessage: null,
        ),
      );
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

  ServiceControl? _findServiceById(String id, List<ServiceControl> services) {
    for (final service in services) {
      if (service.service.wireValue == id) {
        return service;
      }
    }
    return null;
  }
}
