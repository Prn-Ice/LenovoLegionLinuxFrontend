import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../core/theme/legion_accent.dart';
import '../../../core/widgets/legion_mark.dart';
import '../models/platform_event.dart';

/// Compact readout only; window placement, timing and event delivery are native
/// integration responsibilities, not behavior provided by this widget.
class PlatformOsd extends StatelessWidget {
  const PlatformOsd({super.key, required this.event});

  final PlatformEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent =
        LegionAccent.fromPowerModeValue(event.powerModeValue)?.color ??
        scheme.primary;
    final (title, value, icon) = switch (event) {
      PowerModeChanged(:final label) => (
        'Power mode',
        _available(label),
        YaruIcons.power,
      ),
      KeyboardBrightnessChanged(:final fraction) => (
        'Keyboard brightness',
        _brightness(fraction),
        YaruIcons.keyboard,
      ),
      FanBoostChanged(:final enabled) => (
        'Fan boost',
        enabled == null ? 'Unavailable' : (enabled ? 'On' : 'Off'),
        YaruIcons.snow,
      ),
      AutomationChanged(:final description) => (
        'Automation',
        _available(description),
        null,
      ),
    };
    final brightness = event is KeyboardBrightnessChanged
        ? (event as KeyboardBrightnessChanged).fraction
        : null;
    final validBrightness =
        brightness != null &&
        brightness.isFinite &&
        brightness >= 0 &&
        brightness <= 1;

    return Semantics(
      container: true,
      label: '$title: $value',
      child: ExcludeSemantics(
        child: Material(
          color: scheme.surfaceContainerHighest,
          elevation: 8,
          shadowColor: scheme.shadow,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: SingleChildScrollView(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon == null)
                      LegionMark(color: accent, size: 28)
                    else
                      Icon(icon, color: accent, size: 28),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.bodySmall),
                          const SizedBox(height: 3),
                          Text(value, style: theme.textTheme.titleSmall),
                          if (validBrightness) ...[
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: brightness,
                              color: accent,
                              backgroundColor: scheme.onSurface.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _available(String? value) =>
    value == null || value.trim().isEmpty ? 'Unavailable' : value;

String _brightness(double? fraction) {
  if (fraction == null || !fraction.isFinite || fraction < 0 || fraction > 1) {
    return 'Unavailable';
  }
  return '${(fraction * 100).round()}%';
}
