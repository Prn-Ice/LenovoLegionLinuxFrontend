import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../core/theme/legion_accent.dart';
import '../../../core/widgets/legion_mark.dart';

/// Dashboard mode hero: a power-mode [YaruChoiceChipBar] selector above an
/// accent-tinted banner that names the current mode and its description, with
/// the Legion mark. The accent follows the selected mode.
class ModeHero extends StatelessWidget {
  const ModeHero({
    super.key,
    required this.accent,
    required this.label,
    required this.description,
    required this.availableModes,
    required this.selectedMode,
    required this.isApplying,
    required this.onModeSelected,
  });

  final Color accent;

  /// Display label + description for the *current* mode (banner text).
  final String label;
  final String description;

  /// Raw platform-profile values, e.g. `quiet`, `balanced-performance`.
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

    return YaruSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (availableModes.isEmpty)
            const Text('No writable power modes available.')
          else
            YaruChoiceChipBar(
              labels: availableModes
                  .map((mode) => Text(_modeLabel(mode)))
                  .toList(growable: false),
              isSelected: availableModes
                  .map((mode) => selected == mode)
                  .toList(growable: false),
              onSelected: isApplying ? null : onModeSelected,
            ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                accent.withValues(alpha: 0.14),
                scheme.surface,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  LegionMark(color: accent, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: label,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                          if (description.isNotEmpty)
                            TextSpan(
                              text: ' — $description',
                              style: textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Friendly chip label, reusing the accent mapping so `balanced-performance`
  /// reads as "Custom" like the rest of the app; falls back to the raw value.
  static String _modeLabel(String mode) =>
      LegionAccent.fromPowerModeValue(mode)?.label ?? mode;
}
