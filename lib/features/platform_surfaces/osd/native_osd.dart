import 'package:flutter/services.dart';

import '../models/platform_event.dart';

enum OsdDelivery { shown, suppressed, unavailable }

/// Presentation-only boundary. Call only after authoritative feature readback.
///
/// The owner supplies the live preference and foreground state, and must dispose
/// this instance with its feature listener. No subscriptions or hardware writes
/// are created here. Native code owns replacement and the bounded hide timer.
class NativeOsd {
  NativeOsd({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('io.github.prnice.legion/platform_osd');

  final MethodChannel _channel;
  bool _disposed = false;
  Future<void>? _disposal;

  /// False includes Wayland: GTK3 has no portable layer-shell placement API.
  Future<bool> isSupported() async {
    if (_disposed) return false;
    try {
      return await _channel.invokeMethod<bool>('capabilities') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<OsdDelivery> showConfirmed(
    PlatformEvent event, {
    required bool enabled,
    required bool mainWindowVisible,
    Duration duration = const Duration(seconds: 2),
  }) async {
    if (_disposed || !enabled || mainWindowVisible) {
      return OsdDelivery.suppressed;
    }
    final content = _content(event);
    // Unavailable/unknown values are not confirmed changes.
    if (content == null) return OsdDelivery.suppressed;
    try {
      final shown = await _channel.invokeMethod<bool>('show', {
        'title': content.$1,
        'value': content.$2,
        'durationMs': duration.inMilliseconds.clamp(500, 5000),
      });
      return shown == true ? OsdDelivery.shown : OsdDelivery.unavailable;
    } on MissingPluginException {
      return OsdDelivery.unavailable;
    } on PlatformException {
      return OsdDelivery.unavailable;
    }
  }

  /// Also call when the preference is disabled or the main window is revealed.
  Future<void> hide() async {
    if (_disposed) return;
    await _hide();
  }

  Future<void> _hide() async {
    try {
      await _channel.invokeMethod<void>('hide');
    } on MissingPluginException {
      // Unsupported platforms have no owned popup to release.
    } on PlatformException {
      // Native teardown remains responsible for releasing its popup and timer.
    }
  }

  Future<void> dispose() {
    if (_disposal != null) return _disposal!;
    _disposed = true;
    return _disposal = _hide();
  }
}

(String, String)? _content(PlatformEvent event) {
  final (title, value) = switch (event) {
    PowerModeChanged(:final label) => ('Power mode', label),
    KeyboardBrightnessChanged(:final fraction) => (
      'Keyboard brightness',
      fraction != null && fraction.isFinite && fraction >= 0 && fraction <= 1
          ? '${(fraction * 100).round()}%'
          : null,
    ),
    FanBoostChanged(:final enabled) => (
      'Fan boost',
      enabled == null ? null : (enabled ? 'On' : 'Off'),
    ),
    AutomationChanged(:final description) => ('Automation', description),
  };
  if (value == null || value.trim().isEmpty) return null;
  // Bound native layout and message size, including externally supplied labels.
  return (title, String.fromCharCodes(value.runes.take(240)));
}
