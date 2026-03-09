import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

import '../repository/live_sensor_repository.dart';
import 'live_sensor_event.dart';
import 'live_sensor_state.dart';

class LiveSensorBloc extends Bloc<LiveSensorEvent, LiveSensorState> {
  LiveSensorBloc({
    required LiveSensorRepository repository,
    Duration pollInterval = const Duration(seconds: 2),
  })  : _repository = repository,
        _pollInterval = pollInterval,
        super(LiveSensorState.initial()) {
    on<LiveSensorStarted>(_onStarted);
    on<LiveSensorTicked>(_onTicked);
  }

  final LiveSensorRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _refreshInFlight = false;

  Future<void> _onStarted(
    LiveSensorStarted event,
    Emitter<LiveSensorState> emit,
  ) async {
    if (_started) return;
    _started = true;
    await _reload(emit);
    _pollTimer = Timer.periodic(
      _pollInterval,
      (_) => add(const LiveSensorTicked()),
    );
  }

  Future<void> _onTicked(
    LiveSensorTicked event,
    Emitter<LiveSensorState> emit,
  ) async {
    await _reload(emit);
  }

  Future<void> _reload(Emitter<LiveSensorState> emit) async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final snapshot = await _repository.loadSnapshot();
      emit(state.copyWith(snapshot: snapshot, isLoading: false, errorMessage: null));
    } catch (error) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to read sensors: $error',
      ));
    } finally {
      _refreshInFlight = false;
    }
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    return super.close();
  }
}
