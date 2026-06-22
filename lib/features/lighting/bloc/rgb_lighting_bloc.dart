import 'dart:ui' show Color;

import 'package:riverbloc/riverbloc.dart';

import '../repository/rgb_lighting_repository.dart';
import 'rgb_lighting_event.dart';
import 'rgb_lighting_state.dart';

/// Drives per-key keyboard RGB through [RgbLightingRepository] (OpenRGB).
class RgbLightingBloc extends Bloc<RgbLightingEvent, RgbLightingState> {
  RgbLightingBloc({required RgbLightingRepository repository})
    : _repository = repository,
      super(const RgbLightingState()) {
    on<RgbLightingStarted>(_onStarted);
    on<RgbLightingRefreshRequested>(_onStarted);
    on<RgbModeSelected>(_onModeSelected);
    on<RgbColorSelected>(_onColorSelected);
    on<RgbBrightnessChanged>(_onBrightnessChanged);
    on<RgbKeyPainted>(_onKeyPainted);
    on<RgbAllKeysFilled>(_onAllKeysFilled);
  }

  final RgbLightingRepository _repository;

  static const Color _off = Color(0xFF000000);

  Future<void> _onStarted(
    RgbLightingEvent event,
    Emitter<RgbLightingState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      final device = await _repository.loadKeyboard();
      if (device == null) {
        emit(state.copyWith(available: false, device: null, isLoading: false));
        return;
      }
      emit(
        state.copyWith(
          available: true,
          device: device,
          activeMode: device.activeMode,
          keyColors: List<Color>.filled(device.ledCount, _off),
          isLoading: false,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          available: false,
          isLoading: false,
          errorMessage: '$error',
        ),
      );
    }
  }

  Future<void> _onModeSelected(
    RgbModeSelected event,
    Emitter<RgbLightingState> emit,
  ) async {
    final device = state.device;
    if (device == null) return;
    emit(state.copyWith(activeMode: event.mode, isApplying: true));
    await _guard(
      emit,
      () => _repository.applyMode(
        device,
        event.mode,
        color: state.selectedColor,
        brightness: state.brightness,
      ),
    );
  }

  void _onColorSelected(
    RgbColorSelected event,
    Emitter<RgbLightingState> emit,
  ) {
    emit(state.copyWith(selectedColor: event.color));
  }

  Future<void> _onBrightnessChanged(
    RgbBrightnessChanged event,
    Emitter<RgbLightingState> emit,
  ) async {
    final device = state.device;
    if (device == null) return;
    emit(state.copyWith(brightness: event.brightness, isApplying: true));
    await _guard(
      emit,
      () => _repository.setBrightness(device, event.brightness),
    );
  }

  Future<void> _onKeyPainted(
    RgbKeyPainted event,
    Emitter<RgbLightingState> emit,
  ) async {
    final device = state.device;
    if (device == null) return;
    if (event.ledIndex < 0 || event.ledIndex >= state.keyColors.length) return;
    final colors = [...state.keyColors];
    colors[event.ledIndex] = state.selectedColor;
    emit(
      state.copyWith(keyColors: colors, activeMode: 'Direct', isApplying: true),
    );
    await _guard(
      emit,
      () =>
          _repository.applyDirect(device, colors, brightness: state.brightness),
    );
  }

  Future<void> _onAllKeysFilled(
    RgbAllKeysFilled event,
    Emitter<RgbLightingState> emit,
  ) async {
    final device = state.device;
    if (device == null) return;
    final colors = List<Color>.filled(device.ledCount, event.color);
    emit(
      state.copyWith(
        keyColors: colors,
        selectedColor: event.color,
        activeMode: 'Direct',
        isApplying: true,
      ),
    );
    await _guard(
      emit,
      () =>
          _repository.applyDirect(device, colors, brightness: state.brightness),
    );
  }

  /// Runs an apply action, clearing [isApplying] and surfacing any error.
  Future<void> _guard(
    Emitter<RgbLightingState> emit,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      emit(state.copyWith(isApplying: false, errorMessage: null));
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
    }
  }
}
