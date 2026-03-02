import 'package:riverbloc/riverbloc.dart';

import '../models/service_control.dart';
import '../repository/settings_repository.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc({required SettingsRepository repository})
    : _repository = repository,
      super(SettingsState.initial()) {
    on<SettingsStarted>(_onStarted);
    on<SettingsRefreshRequested>(_onRefreshRequested);
    on<SettingsServiceToggled>(_onServiceToggled);
  }

  final SettingsRepository _repository;

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
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
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
          errorMessage: 'Failed to load settings: $error',
        ),
      );
    }
  }

  ServiceControl? _findServiceById(String id, List<ServiceControl> services) {
    for (final service in services) {
      if (service.id == id) {
        return service;
      }
    }
    return null;
  }
}
