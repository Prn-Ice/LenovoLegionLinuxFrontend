import 'dart:ui' show Color;

import 'package:riverbloc/riverbloc.dart';

import '../../../core/models/app_failure.dart';
import '../models/keyboard_layout.dart';
import '../models/rgb_lighting_device.dart';
import '../models/rgb_lighting_snapshot.dart';
import '../repository/rgb_lighting_repository.dart';
import '../repository/rgb_lighting_store.dart';
import '../repository/spectrum_rgb_repository.dart';
import '../services/spectrum_effects.dart';
import '../services/spectrum_effect_engine.dart';
import 'rgb_lighting_event.dart';
import 'rgb_lighting_state.dart';

/// Owns keyboard edits, saved profiles, and queued backend writes.
class RgbLightingBloc extends Bloc<RgbLightingEvent, RgbLightingState> {
  RgbLightingBloc({
    required RgbLightingRepository repository,
    SpectrumRgbRepository? nativeRepository,
    RgbLightingStore? store,
    SpectrumEffectEngine? effectEngine,
  }) : _repository = repository,
       _native = nativeRepository,
       _store = store,
       _effectEngine = effectEngine,
       super(const RgbLightingState()) {
    // Startup, manual edits and mode-triggered profiles share one write queue.
    on<RgbLightingEvent>((event, emit) async {
      if (_closing) return;
      try {
        switch (event) {
          case RgbErrorDismissed():
            if (identical(state.errorMessage, event.error)) {
              emit(state.copyWith(errorDismissed: true));
            }
            return;
          case RgbAnimationFailed():
            emit(
              state.copyWith(
                errorMessage: AppFailure(
                  'Keyboard animation stopped. Check the keyboard connection in Lighting, then apply the profile again.',
                  details: '${event.error}',
                ),
              ),
            );
          case RgbLightingStarted() || RgbLightingRefreshRequested():
            await _onStarted(event, emit);
          case RgbModeSelected():
            await _onModeSelected(event, emit);
          case RgbColorSelected():
            await _onColorSelected(event, emit);
          case RgbBrightnessChanged():
            await _onBrightnessChanged(event, emit);
          case RgbKeyPainted():
            await _onKeyPainted(event, emit);
          case RgbKeyErased():
            await _onKeyErased(event, emit);
          case RgbKeyPicked():
            _onKeyPicked(event, emit);
          case RgbRegionFilled():
            await _onRegionFilled(event, emit);
          case RgbAllKeysFilled():
            await _onAllKeysFilled(event, emit);
          case RgbEffectAssigned():
            _onEffectAssigned(event, emit);
          case RgbEffectsCleared():
            await _onEffectsCleared(event, emit);
          case RgbScopeEffectCleared():
            await _onScopeEffectCleared(event, emit);
          case RgbProfileSaved():
            await _onProfileSaved(event, emit);
          case RgbProfileLoaded():
            await _onProfileLoaded(event, emit);
          case RgbProfileDeleted():
            await _onProfileDeleted(event, emit);
        }
        if (!_closing &&
            state.available &&
            !state.isLoading &&
            state.errorMessage == null) {
          await _store?.save(_snapshotOf(state));
        }
      } catch (error) {
        if (_closing) return;
        emit(state.copyWith(isApplying: false, errorMessage: error));
      }
    }, transformer: (events, mapper) => events.asyncExpand(mapper));
  }

  final RgbLightingRepository _repository;
  final SpectrumRgbRepository? _native;
  final RgbLightingStore? _store;
  final SpectrumEffectEngine? _effectEngine;
  bool _closing = false;

  static const Color _off = Color(0xFF000000);

  @override
  void onChange(Change<RgbLightingState> change) {
    super.onChange(change);
    final next = change.nextState;
    _effectEngine?.configure(
      base: next.keyColors,
      leds: next.device?.leds ?? const [],
      effects:
          !_closing &&
              next.available &&
              next.nativeAvailable &&
              !next.isLoading &&
              !next.isApplying &&
              next.errorMessage == null &&
              next.activeMode == 'Direct'
          ? next.effects
          : const [],
      onError: (error) {
        if (!_closing) add(RgbAnimationFailed(error));
      },
    );
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
    emit(
      state.copyWith(
        isLoading: true,
        errorMessage: null,
        profileNames: _store?.profileNames() ?? const [],
      ),
    );
    String? nativeError;
    try {
      var nativeOk = false;
      try {
        nativeOk = _native?.isAvailable ?? false;
      } catch (error) {
        nativeError = '$error';
      }
      RgbLightingDevice? device;
      try {
        device = await _repository.loadKeyboard();
      } catch (_) {
        // OpenRGB is optional, and a failed probe must not hide a usable
        // native Spectrum keyboard.
        if (!nativeOk) rethrow;
      }
      device ??= _syntheticNativeDevice(nativeOk);
      if (_closing) return;
      if (device == null) {
        emit(
          state.copyWith(
            available: false,
            device: null,
            isLoading: false,
            nativeAvailable: false,
            nativeAvailabilityError: nativeError,
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
          device: device,
          available: true,
          nativeAvailable: nativeOk,
        ),
      );
      if (snapshot != null) {
        await _writeSnapshot(device, snapshot, nativeAvailable: nativeOk);
        if (_closing) return;
      }
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
          keyboardLayout: nativeOk
              ? _native!.keyboardProfile!.layout
              : kLegionAnsiLayout,
          nativeAvailabilityError: nativeError,
        ),
      );
    } catch (error) {
      if (_closing) return;
      emit(
        state.copyWith(
          available: state.device != null,
          isLoading: false,
          errorMessage: error,
          nativeAvailabilityError: nativeError,
        ),
      );
    }
  }

  /// A device synthesized from the native LED map, for when OpenRGB isn't
  /// running but the keyboard is present — makes native fully standalone.
  RgbLightingDevice? _syntheticNativeDevice(bool nativeOk) {
    if (!nativeOk) return null;
    final profile = _native?.keyboardProfile;
    if (profile == null) return null;
    return RgbLightingDevice(
      index: 0,
      name: 'Legion Keyboard',
      type: 'Keyboard',
      modes: const ['Direct', 'Static'],
      activeMode: 'Direct',
      leds: profile.ledValues.keys.toList(),
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
    await _applyOpenRgb(
      emit,
      () => _repository.applyMode(
        device,
        mode,
        color: state.selectedColor,
        brightness: state.brightness,
      ),
      appliedState: state.copyWith(activeMode: mode, directColors: savedDirect),
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
    await _applyOpenRgb(
      emit,
      () => _repository.setBrightness(device, event.brightness),
      appliedState: state.copyWith(brightness: event.brightness),
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
    emit(state.copyWith(effects: updated, activeMode: 'Direct'));
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

  Future<void> _onProfileSaved(
    RgbProfileSaved event,
    Emitter<RgbLightingState> emit,
  ) async {
    final name = event.name.trim();
    if (name.isEmpty) return;
    await _store?.saveProfile(name, _snapshotOf(state));
    if (_closing) return;
    if (!state.profileNames.contains(name)) {
      emit(state.copyWith(profileNames: [...state.profileNames, name]));
    }
  }

  Future<void> _onProfileLoaded(
    RgbProfileLoaded event,
    Emitter<RgbLightingState> emit,
  ) async {
    emit(state.copyWith(isApplying: true, errorMessage: null));
    try {
      final device = state.device;
      final snapshot = _store?.loadProfile(event.name);
      if (snapshot == null) {
        throw StateError(
          'Saved profile "${event.name}" no longer exists. Choose another profile in Automation or save it again in Lighting.',
        );
      }
      if (device == null || !state.available) {
        throw StateError(
          'No RGB keyboard is available. Open Lighting and reconnect the keyboard backend, then retry.',
        );
      }
      await _writeSnapshot(
        device,
        snapshot,
        nativeAvailable: state.nativeAvailable,
      );
      if (_closing) return;
      emit(
        state.copyWith(
          isApplying: false,
          keyColors: snapshot.keyColors,
          directColors: snapshot.keyColors,
          selectedColor: snapshot.selectedColor,
          brightness: snapshot.brightness,
          activeMode: snapshot.activeMode ?? 'Direct',
          effects: snapshot.effects,
        ),
      );
    } catch (error) {
      if (_closing) return;
      emit(
        state.copyWith(
          isApplying: false,
          errorMessage: AppFailure.from(
            error,
            message:
                'Could not apply keyboard profile "${event.name}". The keyboard may be partly updated. Check the profile in Lighting, then retry from Automation.',
          ),
        ),
      );
    }
  }

  Future<void> _writeSnapshot(
    RgbLightingDevice device,
    RgbLightingSnapshot snapshot, {
    required bool nativeAvailable,
  }) async {
    if (snapshot.keyColors.length != device.ledCount) {
      throw StateError(
        'This profile was saved for a different keyboard. Save a new profile in Lighting.',
      );
    }
    final mode = snapshot.activeMode ?? 'Direct';
    if (!device.modes.contains(mode)) {
      throw StateError(
        'The keyboard backend does not support the saved "$mode" effect.',
      );
    }
    if (mode == 'Direct' &&
        snapshot.effects.isNotEmpty &&
        (!nativeAvailable || _effectEngine == null)) {
      throw StateError(
        'This profile needs the native Spectrum animation backend.',
      );
    }
    if (nativeAvailable &&
        _native != null &&
        (mode == 'Direct' || mode == 'Static')) {
      if (!_native.paint(device.leds, snapshot.keyColors)) {
        throw StateError('The keyboard did not accept its colors.');
      }
      if (!_native.setBrightness(snapshot.brightness)) {
        throw StateError('The keyboard did not accept its brightness.');
      }
    } else if (mode == 'Direct') {
      await _repository.applyDirect(
        device,
        snapshot.keyColors,
        brightness: snapshot.brightness,
      );
    } else {
      await _repository.applyMode(
        device,
        mode,
        color: snapshot.selectedColor,
        brightness: snapshot.brightness,
      );
    }
  }

  Future<void> _onProfileDeleted(
    RgbProfileDeleted event,
    Emitter<RgbLightingState> emit,
  ) async {
    await _store?.deleteProfile(event.name);
    if (_closing) return;
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
    await _applyOpenRgb(
      emit,
      () =>
          _repository.applyDirect(device, colors, brightness: state.brightness),
      appliedState: state.copyWith(
        keyColors: colors,
        activeMode: activeMode,
        selectedColor: selectedColor,
      ),
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
    await _applyOpenRgb(
      emit,
      () => _repository.applyMode(
        device,
        'Static',
        color: state.selectedColor,
        brightness: state.brightness,
      ),
      appliedState: state.copyWith(keyColors: filled, activeMode: 'Static'),
    );
  }

  /// Keeps the previous lighting values until the OpenRGB command succeeds.
  Future<void> _applyOpenRgb(
    Emitter<RgbLightingState> emit,
    Future<void> Function() action, {
    required RgbLightingState appliedState,
  }) async {
    emit(state.copyWith(isApplying: true, errorMessage: null));
    try {
      await action();
      if (_closing) return;
      emit(appliedState.copyWith(isApplying: false, errorMessage: null));
    } catch (error) {
      if (_closing) return;
      emit(state.copyWith(isApplying: false, errorMessage: error));
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    _effectEngine?.configure(base: const [], leds: const [], effects: const []);
    return super.close();
  }
}
