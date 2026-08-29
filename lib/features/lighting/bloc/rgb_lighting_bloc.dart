import 'dart:ui' show Color;

import 'package:riverbloc/riverbloc.dart';

import '../models/rgb_lighting_device.dart';
import '../models/rgb_lighting_snapshot.dart';
import '../repository/rgb_lighting_repository.dart';
import '../repository/rgb_lighting_store.dart';
import '../repository/spectrum_rgb_repository.dart';
import '../services/spectrum_effects.dart';
import '../services/spectrum_led_map.dart';
import 'rgb_lighting_event.dart';
import 'rgb_lighting_state.dart';

/// Drives per-key keyboard RGB through [RgbLightingRepository] (OpenRGB).
class RgbLightingBloc extends Bloc<RgbLightingEvent, RgbLightingState> {
  RgbLightingBloc({
    required RgbLightingRepository repository,
    SpectrumRgbRepository? nativeRepository,
    RgbLightingStore? store,
  }) : _repository = repository,
       _native = nativeRepository,
       _store = store,
       super(const RgbLightingState()) {
    on<RgbLightingStarted>(_onStarted);
    on<RgbLightingRefreshRequested>(_onStarted);
    on<RgbModeSelected>(_onModeSelected);
    on<RgbColorSelected>(_onColorSelected);
    on<RgbBrightnessChanged>(_onBrightnessChanged);
    on<RgbKeyPainted>(_onKeyPainted);
    on<RgbKeyErased>(_onKeyErased);
    on<RgbKeyPicked>(_onKeyPicked);
    on<RgbRegionFilled>(_onRegionFilled);
    on<RgbAllKeysFilled>(_onAllKeysFilled);
    on<RgbEffectAssigned>(_onEffectAssigned);
    on<RgbEffectsCleared>(_onEffectsCleared);
    on<RgbScopeEffectCleared>(_onScopeEffectCleared);
    on<RgbProfileSaved>(_onProfileSaved);
    on<RgbProfileLoaded>(_onProfileLoaded);
    on<RgbProfileDeleted>(_onProfileDeleted);
  }

  final RgbLightingRepository _repository;
  final SpectrumRgbRepository? _native;
  final RgbLightingStore? _store;

  static const Color _off = Color(0xFF000000);

  @override
  void onChange(Change<RgbLightingState> change) {
    super.onChange(change);
    final next = change.nextState;
    if (next.available && next.device != null && !next.isLoading) {
      _store?.save(_snapshotOf(next));
    }
  }

  RgbLightingSnapshot _snapshotOf(RgbLightingState s) => RgbLightingSnapshot(
    keyColors: s.keyColors,
    selectedColor: s.selectedColor,
    brightness: s.brightness,
    activeMode: s.activeMode,
    effects: s.effects,
  );

  Future<void> _onStarted(
    RgbLightingEvent event,
    Emitter<RgbLightingState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      final nativeOk = _native?.isAvailable ?? false;
      final device =
          await _repository.loadKeyboard() ?? _syntheticNativeDevice(nativeOk);
      if (device == null) {
        emit(
          state.copyWith(
            available: false,
            device: null,
            isLoading: false,
            nativeAvailable: false,
          ),
        );
        return;
      }
      // Restore the remembered painting when it fits this keyboard.
      final saved = _store?.load();
      final snapshot =
          (saved != null && saved.keyColors.length == device.ledCount)
          ? saved
          : null;
      final keyColors =
          snapshot?.keyColors ?? List<Color>.filled(device.ledCount, _off);
      emit(
        state.copyWith(
          available: true,
          device: device,
          activeMode: snapshot?.activeMode ?? device.activeMode,
          keyColors: keyColors,
          selectedColor: snapshot?.selectedColor,
          brightness: snapshot?.brightness,
          effects: snapshot?.effects ?? const [],
          profileNames: _store?.profileNames() ?? const [],
          isLoading: false,
          nativeAvailable: nativeOk,
        ),
      );
      // Persist & re-apply: push the remembered painting back to the keyboard.
      if (snapshot != null) {
        if (nativeOk && _native != null) {
          _native.paint(device.leds, keyColors);
          _native.setBrightness(snapshot.brightness);
        } else {
          await _repository.applyDirect(
            device,
            keyColors,
            brightness: snapshot.brightness,
          );
        }
      }
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

  /// A device synthesized from the native LED map, for when OpenRGB isn't
  /// running but the keyboard is present — makes native fully standalone.
  RgbLightingDevice? _syntheticNativeDevice(bool nativeOk) {
    if (!nativeOk) return null;
    return RgbLightingDevice(
      index: 0,
      name: 'Legion Keyboard',
      type: 'Keyboard',
      modes: const ['Direct', 'Static'],
      activeMode: 'Direct',
      leds: kSpectrumLedValues.keys.toList(),
    );
  }

  Future<void> _onModeSelected(
    RgbModeSelected event,
    Emitter<RgbLightingState> emit,
  ) async {
    final device = state.device;
    if (device == null) return;
    final mode = event.mode;

    // Remember the Direct painting before leaving it, so Direct can restore it.
    final savedDirect = state.activeMode == 'Direct'
        ? List<Color>.of(state.keyColors)
        : state.directColors;

    if (mode == 'Direct') {
      final restored = state.directColors.length == device.ledCount
          ? state.directColors
          : state.keyColors;
      await _applyColors(emit, device, restored, activeMode: 'Direct');
      return;
    }

    if (mode == 'Static') {
      // Fill the whole keyboard with the selected color to signal Static mode.
      final filled = List<Color>.filled(device.ledCount, state.selectedColor);
      emit(state.copyWith(directColors: savedDirect));
      await _applyStatic(emit, device, filled);
      return;
    }

    // Hardware animation effect (Rainbow Wave, Color Pulse, …) — OpenRGB only.
    emit(
      state.copyWith(
        activeMode: mode,
        directColors: savedDirect,
        isApplying: true,
      ),
    );
    await _guard(
      emit,
      () => _repository.applyMode(
        device,
        mode,
        color: state.selectedColor,
        brightness: state.brightness,
      ),
    );
  }

  Future<void> _onColorSelected(
    RgbColorSelected event,
    Emitter<RgbLightingState> emit,
  ) async {
    final device = state.device;
    // In Static the color is the keyboard color, so apply it immediately.
    if (state.activeMode == 'Static' && device != null) {
      final filled = List<Color>.filled(device.ledCount, event.color);
      emit(state.copyWith(selectedColor: event.color));
      await _applyStatic(emit, device, filled);
      return;
    }
    emit(state.copyWith(selectedColor: event.color));
  }

  Future<void> _onBrightnessChanged(
    RgbBrightnessChanged event,
    Emitter<RgbLightingState> emit,
  ) async {
    final device = state.device;
    if (device == null) return;
    if (state.nativeAvailable && _native != null) {
      _native.setBrightness(event.brightness);
      emit(state.copyWith(brightness: event.brightness));
      return;
    }
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
    final colors = _withLed(event.ledIndex, state.selectedColor);
    if (colors == null) return;
    await _applyColors(emit, state.device!, colors);
  }

  Future<void> _onKeyErased(
    RgbKeyErased event,
    Emitter<RgbLightingState> emit,
  ) async {
    final colors = _withLed(event.ledIndex, _off);
    if (colors == null) return;
    await _applyColors(emit, state.device!, colors);
  }

  void _onKeyPicked(RgbKeyPicked event, Emitter<RgbLightingState> emit) {
    final index = event.ledIndex;
    if (index < 0 || index >= state.keyColors.length) return;
    final color = state.keyColors[index];
    if (color == _off) return; // nothing to pick from an unlit key
    emit(state.copyWith(selectedColor: color));
  }

  Future<void> _onRegionFilled(
    RgbRegionFilled event,
    Emitter<RgbLightingState> emit,
  ) async {
    final device = state.device;
    if (device == null) return;
    final colors = [...state.keyColors];
    for (final index in event.ledIndices) {
      if (index >= 0 && index < colors.length) {
        colors[index] = state.selectedColor;
      }
    }
    await _applyColors(emit, device, colors);
  }

  Future<void> _onAllKeysFilled(
    RgbAllKeysFilled event,
    Emitter<RgbLightingState> emit,
  ) async {
    final device = state.device;
    if (device == null) return;
    final colors = List<Color>.filled(device.ledCount, event.color);
    await _applyColors(emit, device, colors, selectedColor: event.color);
  }

  void _onEffectAssigned(
    RgbEffectAssigned event,
    Emitter<RgbLightingState> emit,
  ) {
    final updated = [
      for (final effect in state.effects)
        if (effect.label != event.scope) effect,
      SpectrumRegionEffect(
        ledIndices: event.ledIndices,
        effect: event.effect,
        color: state.selectedColor,
        label: event.scope,
      ),
    ];
    emit(state.copyWith(effects: updated));
  }

  Future<void> _onEffectsCleared(
    RgbEffectsCleared event,
    Emitter<RgbLightingState> emit,
  ) async {
    emit(state.copyWith(effects: const []));
    // Re-push the static painting so the keyboard leaves the last animated frame.
    final device = state.device;
    if (device != null) await _applyColors(emit, device, state.keyColors);
  }

  Future<void> _onScopeEffectCleared(
    RgbScopeEffectCleared event,
    Emitter<RgbLightingState> emit,
  ) async {
    final remaining = [
      for (final effect in state.effects)
        if (effect.label != event.scope) effect,
    ];
    if (remaining.length == state.effects.length) return;
    emit(state.copyWith(effects: remaining));
    // When the last effect goes, re-push the static painting to the keyboard.
    if (remaining.isEmpty) {
      final device = state.device;
      if (device != null) await _applyColors(emit, device, state.keyColors);
    }
  }

  void _onProfileSaved(RgbProfileSaved event, Emitter<RgbLightingState> emit) {
    final name = event.name.trim();
    if (name.isEmpty) return;
    _store?.saveProfile(name, _snapshotOf(state));
    if (!state.profileNames.contains(name)) {
      emit(state.copyWith(profileNames: [...state.profileNames, name]));
    }
  }

  Future<void> _onProfileLoaded(
    RgbProfileLoaded event,
    Emitter<RgbLightingState> emit,
  ) async {
    final device = state.device;
    final snapshot = _store?.loadProfile(event.name);
    if (device == null ||
        snapshot == null ||
        snapshot.keyColors.length != device.ledCount) {
      return;
    }
    emit(
      state.copyWith(
        keyColors: snapshot.keyColors,
        selectedColor: snapshot.selectedColor,
        brightness: snapshot.brightness,
        activeMode: snapshot.activeMode,
        effects: snapshot.effects,
      ),
    );
    if (state.nativeAvailable && _native != null) {
      _native.paint(device.leds, snapshot.keyColors);
      _native.setBrightness(snapshot.brightness);
    } else {
      await _repository.applyDirect(
        device,
        snapshot.keyColors,
        brightness: snapshot.brightness,
      );
    }
  }

  void _onProfileDeleted(
    RgbProfileDeleted event,
    Emitter<RgbLightingState> emit,
  ) {
    _store?.deleteProfile(event.name);
    emit(
      state.copyWith(
        profileNames: state.profileNames
            .where((name) => name != event.name)
            .toList(),
      ),
    );
  }

  /// A copy of the key buffer with [ledIndex] set to [color], or null if the
  /// device is missing or the index is out of range.
  List<Color>? _withLed(int ledIndex, Color color) {
    if (state.device == null) return null;
    if (ledIndex < 0 || ledIndex >= state.keyColors.length) return null;
    final colors = [...state.keyColors];
    colors[ledIndex] = color;
    return colors;
  }

  /// Pushes a Direct [colors] buffer to the keyboard (native frame when
  /// available, else the OpenRGB CLI) and records it in state.
  Future<void> _applyColors(
    Emitter<RgbLightingState> emit,
    RgbLightingDevice device,
    List<Color> colors, {
    Color? selectedColor,
    String activeMode = 'Direct',
  }) async {
    if (state.nativeAvailable && _native != null) {
      _native.paint(device.leds, colors);
      emit(
        state.copyWith(
          keyColors: colors,
          activeMode: activeMode,
          selectedColor: selectedColor,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        keyColors: colors,
        activeMode: activeMode,
        selectedColor: selectedColor,
        isApplying: true,
      ),
    );
    await _guard(
      emit,
      () =>
          _repository.applyDirect(device, colors, brightness: state.brightness),
    );
  }

  /// Applies a uniform Static fill — a native Direct frame when available, else
  /// the OpenRGB hardware "Static" mode. Keeps [keyColors] filled for the view.
  Future<void> _applyStatic(
    Emitter<RgbLightingState> emit,
    RgbLightingDevice device,
    List<Color> filled,
  ) async {
    if (state.nativeAvailable && _native != null) {
      _native.paint(device.leds, filled);
      emit(state.copyWith(keyColors: filled, activeMode: 'Static'));
      return;
    }
    emit(
      state.copyWith(keyColors: filled, activeMode: 'Static', isApplying: true),
    );
    await _guard(
      emit,
      () => _repository.applyMode(
        device,
        'Static',
        color: state.selectedColor,
        brightness: state.brightness,
      ),
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
