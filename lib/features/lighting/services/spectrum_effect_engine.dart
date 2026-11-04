import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../repository/spectrum_rgb_repository.dart';
import 'spectrum_effects.dart';

/// Drives [SpectrumRegionEffect]s in real time over the native path. Each tick
/// it composes a frame (base painting + animated overlays), pushes it to the
/// keyboard, and publishes it on [frame] for the live preview. Runs only while
/// there are effects assigned.
class SpectrumEffectEngine {
  SpectrumEffectEngine(this._native, {this.fps = 30});

  final SpectrumRgbRepository _native;
  final int fps;

  /// The current animated frame, or null when nothing is running (the preview
  /// then falls back to the static painting).
  final ValueNotifier<List<Color>?> frame = ValueNotifier<List<Color>?>(null);

  Timer? _timer;
  double _t = 0;
  List<Color> _base = const [];
  List<String> _leds = const [];
  List<SpectrumRegionEffect> _effects = const [];
  void Function(Object)? _onError;
  bool _disposed = false;

  bool get isRunning => _timer != null;

  /// Sets the base painting, LED order and active [effects]; starts the loop
  /// when there is something to animate and stops it when there isn't.
  void configure({
    required List<Color> base,
    required List<String> leds,
    required List<SpectrumRegionEffect> effects,
    void Function(Object)? onError,
  }) {
    if (_disposed) return;
    _base = base;
    _leds = leds;
    _effects = effects;
    _onError = onError;
    if (effects.isEmpty) {
      _stop();
    } else {
      _ensureRunning();
    }
  }

  void _ensureRunning() {
    if (_timer != null) return;
    _t = 0;
    _timer = Timer.periodic(
      Duration(milliseconds: (1000 / fps).round()),
      (_) => _tick(),
    );
  }

  void _tick() {
    _t += 1 / fps;
    final composed = composeEffectFrame(base: _base, effects: _effects, t: _t);
    try {
      if (!_native.paint(_leds, composed)) {
        throw StateError('The keyboard stopped accepting animation frames.');
      }
      frame.value = composed;
    } catch (error) {
      _stop();
      _onError?.call(error);
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    frame.value = null;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    frame.dispose();
  }
}
