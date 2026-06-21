import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../core/theme/legion_accent.dart';
import '../../../core/widgets/legion_mark.dart';
import '../../../core/widgets/metric_text.dart';
import '../../../core/widgets/surface_card.dart';

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

/// Dashboard mode hero: a row of selectable power-mode cards (a colored dot +
/// the mode name, with an accent border when active) above an accent-tinted
/// banner naming the current mode. The accent follows the selected mode.
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
    final selected = selectedMode?.trim();
    final enabled = !isApplying && onModeSelected != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (availableModes.isEmpty)
          const Text('No writable power modes available.')
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < availableModes.length; i++)
                _ModeCard(
                  mode: availableModes[i],
                  selected: selected == availableModes[i],
                  onTap: enabled ? () => onModeSelected!(i) : null,
                ),
            ],
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
                Text(
                  humanizeMode(selected),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                if (facts != null) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      facts!,
                      overflow: TextOverflow.ellipsis,
                      style: monoFactStyle(scheme),
                    ),
                  ),
                ] else
                  const Spacer(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A single selectable mode card: a colored dot (the mode's accent) and its
/// name, with the accent selection border when active.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final String mode;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dotColor =
        LegionAccent.fromPowerModeValue(mode)?.color ?? scheme.primary;

    return SizedBox(
      width: 178,
      child: SurfaceCard(
        color: selected
            ? Color.alphaBlend(
                dotColor.withValues(alpha: 0.13),
                scheme.surfaceContainerHigh,
              )
            : null,
        border: selected ? Border.all(color: dotColor, width: 2) : null,
        padding: EdgeInsets.zero,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(kYaruContainerRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(
                children: [
                  Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      humanizeMode(mode),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
