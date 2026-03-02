import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

import '../repository/dashboard_repository.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  DashboardBloc({
    required DashboardRepository repository,
    Duration pollInterval = const Duration(seconds: 3),
  }) : _repository = repository,
       _pollInterval = pollInterval,
       super(DashboardState.initial()) {
    on<DashboardStarted>(_onStarted);
    on<DashboardRefreshRequested>(_onRefreshRequested);
    on<DashboardTicked>(_onTicked);
    on<DashboardPowerModeSetRequested>(_onPowerModeSetRequested);
    on<DashboardHybridModeSetRequested>(_onHybridModeSetRequested);
    on<DashboardApplyContextFanPresetRequested>(
      _onApplyContextFanPresetRequested,
    );
  }

  final DashboardRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _refreshInFlight = false;

  Future<void> _onStarted(
    DashboardStarted event,
    Emitter<DashboardState> emit,
  ) async {
    if (_started) {
      return;
    }

    _started = true;
    await _loadStatus(emit, showLoading: true);

    _pollTimer = Timer.periodic(_pollInterval, (_) {
      add(const DashboardTicked());
    });
  }

  Future<void> _onRefreshRequested(
    DashboardRefreshRequested event,
    Emitter<DashboardState> emit,
  ) async {
    await _loadStatus(emit, showLoading: true);
  }

  Future<void> _onTicked(
    DashboardTicked event,
    Emitter<DashboardState> emit,
  ) async {
    if (state.isApplying) {
      return;
    }
    await _loadStatus(emit, showLoading: false);
  }

  Future<void> _onPowerModeSetRequested(
    DashboardPowerModeSetRequested event,
    Emitter<DashboardState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setPowerMode(event.mode),
      successMessage: 'Power mode set to "${event.mode}".',
    );
  }

  Future<void> _onHybridModeSetRequested(
    DashboardHybridModeSetRequested event,
    Emitter<DashboardState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setHybridMode(event.enabled),
      successMessage: 'Hybrid mode ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _onApplyContextFanPresetRequested(
    DashboardApplyContextFanPresetRequested event,
    Emitter<DashboardState> emit,
  ) async {
    await _apply(
      emit,
      action: _repository.applyContextFanPreset,
      successMessage: 'Applied current context fan preset.',
    );
  }

  Future<void> _loadStatus(
    Emitter<DashboardState> emit, {
    required bool showLoading,
  }) async {
    if (_refreshInFlight) {
      return;
    }

    _refreshInFlight = true;

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
          snapshot: snapshot,
          isLoading: false,
          hasInitialized: true,
          errorMessage: null,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isLoading: false,
          hasInitialized: true,
          errorMessage: 'Failed to load dashboard state: $error',
        ),
      );
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _apply(
    Emitter<DashboardState> emit, {
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    if (state.isApplying) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await action();
      await _loadStatus(emit, showLoading: false);
      emit(state.copyWith(isApplying: false, noticeMessage: successMessage));
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
    }
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    return super.close();
  }
}
