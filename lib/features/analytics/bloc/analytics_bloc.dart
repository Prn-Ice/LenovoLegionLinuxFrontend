// lib/features/analytics/bloc/analytics_bloc.dart
import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

import '../repository/analytics_repository.dart';
import 'analytics_event.dart';
import 'analytics_state.dart';

class AnalyticsBloc extends Bloc<AnalyticsEvent, AnalyticsState> {
  AnalyticsBloc({
    required AnalyticsRepository repository,
    Duration pollInterval = const Duration(seconds: 3),
  }) : _repository = repository,
       _pollInterval = pollInterval,
       super(AnalyticsState.initial()) {
    on<AnalyticsStarted>(_onStarted);
    on<AnalyticsTicked>(_onTicked);
    on<AnalyticsWindowChanged>(_onWindowChanged);
  }

  final AnalyticsRepository _repository;
  final Duration _pollInterval;
  Timer? _pollTimer;
  bool _started = false;

  Future<void> _onStarted(
    AnalyticsStarted _,
    Emitter<AnalyticsState> emit,
  ) async {
    if (_started) return;
    _started = true;
    await _repository.pruneOldRecords();
    await _tick(emit);
    _pollTimer = Timer.periodic(
      _pollInterval,
      (_) => add(const AnalyticsTicked()),
    );
  }

  Future<void> _onTicked(
    AnalyticsTicked _,
    Emitter<AnalyticsState> emit,
  ) async {
    await _tick(emit);
  }

  Future<void> _onWindowChanged(
    AnalyticsWindowChanged event,
    Emitter<AnalyticsState> emit,
  ) async {
    final since = DateTime.now().subtract(event.window.duration);
    emit(
      state.copyWith(
        window: event.window,
        history: _repository.readHistory(since: since),
      ),
    );
  }

  Future<void> _tick(Emitter<AnalyticsState> emit) async {
    try {
      await _repository.recordReading();
      final since = DateTime.now().subtract(state.window.duration);
      emit(
        state.copyWith(
          history: _repository.readHistory(since: since),
          errorMessage: null,
        ),
      );
    } catch (error) {
      emit(state.copyWith(errorMessage: 'Sensor read failed: $error'));
    }
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    return super.close();
  }
}
