import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../core/theme/legion_accent.dart';
import '../../../core/widgets/legion_mark.dart';
import '../../../core/widgets/metric_text.dart';

/// Title-cases a raw platform-profile value for display: `low-power` -> `Low
/// Power`, `balanced` -> `Balanced`.
String humanizeMode(String? mode) {
  final value = mode?.trim() ?? '';
  if (value.isEmpty) return 'Unknown';
  return value
      .split('-')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

String modeLabel(String? mode) {
  final value = mode?.trim();
  if (value == 'max-power') return 'Extreme';
  return LegionAccent.fromPowerModeValue(value)?.label ?? humanizeMode(value);
}

String modeDescription(String? mode) {
  switch (mode?.trim()) {
    case 'quiet':
    case 'low-power':
    case 'power-saver':
      return 'Keeps heat, noise, and power use low.';
    case 'balanced':
      return 'Quick when you need it, calm when you do not.';
    case 'performance':
      return 'Uses more power and cooling for sustained speed.';
    case 'max-power':
      return 'Allows the highest performance exposed by the controller.';
    case 'balanced-performance':
    case 'custom':
      return 'Uses your controller-provided power and thermal limits.';
    default:
      return 'The active platform power profile.';
  }
}

/// Shared mode hero: Yaru-native selectable power-mode chips above an
/// accent-tinted banner naming the current mode.
class ModeHero extends StatelessWidget {
  const ModeHero({
    super.key,
    required this.accent,
    required this.availableModes,
    required this.selectedMode,
    required this.isApplying,
    required this.onModeSelected,
    this.facts,
  });

  final Color accent;

  /// Raw platform-profile values, e.g. `balanced`, `low-power`.
  final List<String> availableModes;
  final String? selectedMode;
  final bool isApplying;

  /// Invoked with the index into [availableModes]; null disables selection.
  final ValueChanged<int>? onModeSelected;

  /// Optional factual summary shown in the banner (e.g. the mode's power
  /// limits read from sysfs). Null hides it.
  final String? facts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final selected = selectedMode?.trim();
    final enabled = !isApplying && onModeSelected != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (availableModes.isEmpty)
          const Text('No writable power modes available.')
        else
          YaruChoiceChipBar(
            style: YaruChoiceChipBarStyle.wrap,
            spacing: 12,
            wrapRunSpacing: 12,
            selectedFirst: false,
            showCheckMarks: false,
            clearOnSelect: false,
            chipHeight: 44,
            labels: [
              for (var i = 0; i < availableModes.length; i++)
                _ModeChipLabel(mode: availableModes[i]),
            ],
            isSelected: [for (final mode in availableModes) selected == mode],
            onSelected: enabled ? onModeSelected : null,
          ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              accent.withValues(alpha: 0.14),
              scheme.surface,
            ),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                LegionMark(color: accent, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        modeLabel(selected),
                        style: textTheme.titleSmall?.copyWith(color: accent),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        modeDescription(selected),
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                if (facts != null) ...[
                  const SizedBox(width: 14),
                  Text(
                    facts!,
                    overflow: TextOverflow.ellipsis,
                    style: monoFactStyle(scheme),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A compact chip label with the mode's accent and user-facing name.
class _ModeChipLabel extends StatelessWidget {
  const _ModeChipLabel({required this.mode});

  final String mode;

  @override
  Widget build(BuildContext context) {
    final dotColor =
        LegionAccent.fromPowerModeValue(mode)?.color ??
        Theme.of(context).colorScheme.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(modeLabel(mode)),
      ],
    );
  }
}
