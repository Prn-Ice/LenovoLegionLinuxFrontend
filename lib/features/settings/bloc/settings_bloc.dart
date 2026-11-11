import 'package:riverbloc/riverbloc.dart';

import '../../../core/models/app_failure.dart';
import '../../../core/models/control_mode.dart';
import '../repository/control_mode_store.dart';
import '../models/service_control.dart';
import '../repository/appearance_store.dart';
import '../repository/settings_repository.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc({
    required SettingsRepository repository,
    AppearanceStore? appearanceStore,
    ControlModeStore? controlModeStore,
    ControlMode activeControlMode = ControlMode.installedService,
    bool portableControlAvailable = false,
  }) : _repository = repository,
       _appearanceStore = appearanceStore,
       _controlModeStore = controlModeStore,
       _portableControlAvailable = portableControlAvailable,
       super(
         _initialState(appearanceStore).copyWith(
           activeControlMode: activeControlMode,
           nextControlMode: controlModeStore?.load() ?? activeControlMode,
         ),
       ) {
    on<ControlModeChanged>(
      _onControlModeChanged,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
    on<ControlModeErrorDismissed>((event, emit) {
      if (identical(state.controlModeErrorMessage, event.error)) {
        emit(state.copyWith(controlModeErrorMessage: null));
      }
    });
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
  final ControlModeStore? _controlModeStore;
  final bool _portableControlAvailable;

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

  Future<void> _onControlModeChanged(
    ControlModeChanged event,
    Emitter<SettingsState> emit,
  ) async {
    if (event.mode == state.nextControlMode) return;
    emit(
      state.copyWith(isSavingControlMode: true, controlModeErrorMessage: null),
    );
    try {
      if (event.mode == ControlMode.temporaryHelper &&
          !_portableControlAvailable) {
        throw StateError(
          'Temporary hardware control is not available in this build.',
        );
      }
      await _controlModeStore?.save(event.mode);
      if (emit.isDone) return;
      emit(
        state.copyWith(
          nextControlMode: event.mode,
          isSavingControlMode: false,
          controlModeErrorMessage: null,
        ),
      );
    } catch (error) {
      if (emit.isDone) return;
      emit(
        state.copyWith(
          isSavingControlMode: false,
          controlModeErrorMessage: AppFailure(
            'Could not save hardware access preferences. Your previous selection is unchanged. Check that application data is writable and try again.',
            details: error.toString(),
          ),
        ),
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
