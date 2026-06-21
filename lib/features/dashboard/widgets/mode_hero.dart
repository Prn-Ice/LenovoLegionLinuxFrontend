import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../core/theme/legion_accent.dart';
import '../../../core/widgets/legion_mark.dart';

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
  });

  final Color accent;

  /// Raw platform-profile values, e.g. `balanced`, `low-power`.
  final List<String> availableModes;
  final String? selectedMode;
  final bool isApplying;

  /// Invoked with the index into [availableModes]; null disables selection.
  final ValueChanged<int>? onModeSelected;

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
                Expanded(
                  child: Text(
                    humanizeMode(selected),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
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
    final textTheme = Theme.of(context).textTheme;
    final dotColor =
        LegionAccent.fromPowerModeValue(mode)?.color ?? scheme.primary;

    return SizedBox(
      width: 152,
      child: YaruSelectableContainer(
        selected: selected,
        selectionColor: dotColor,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                humanizeMode(mode),
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
