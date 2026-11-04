/// A confirmed change that can later be shown by a desktop surface.
///
/// These values are not emitted automatically. Producers must use authoritative
/// readback where available, rather than treating an attempted write as success.
sealed class PlatformEvent {
  const PlatformEvent({this.powerModeValue});

  /// The current platform profile, used only to resolve the visual accent.
  final String? powerModeValue;
}

final class PowerModeChanged extends PlatformEvent {
  const PowerModeChanged({required this.label, super.powerModeValue});

  /// Human-readable confirmed mode, or null when unavailable.
  final String? label;
}

final class KeyboardBrightnessChanged extends PlatformEvent {
  const KeyboardBrightnessChanged({
    required this.fraction,
    super.powerModeValue,
  });

  /// Confirmed brightness from 0 to 1; null means unavailable.
  final double? fraction;
}

final class FanBoostChanged extends PlatformEvent {
  const FanBoostChanged({required this.enabled, super.powerModeValue});

  final bool? enabled;
}

final class AutomationChanged extends PlatformEvent {
  const AutomationChanged({required this.description, super.powerModeValue});

  /// A truthful description of the completed automation, if available.
  final String? description;
}
