import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/responsive_card_grid.dart';

/// One toggle in the dashboard [QuickControls] hub.
class QuickControl {
  const QuickControl({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;

  /// Null disables the toggle (unsupported, or an action is in flight).
  final ValueChanged<bool>? onChanged;
}

/// The dashboard quick-control hub: each toggle is its own Yaru card (an
/// accent icon tile, label/description, and a switch), laid out in a responsive
/// grid. Decoupled from blocs — the page builds each [QuickControl] with its
/// own already-wired callback.
class QuickControls extends StatelessWidget {
  const QuickControls({
    super.key,
    required this.accent,
    required this.controls,
  });

  final Color accent;
  final List<QuickControl> controls;

  @override
  Widget build(BuildContext context) {
    return ResponsiveCardGrid(
      minCardWidth: 320,
      children: [
        for (final control in controls)
          _QuickControlCard(accent: accent, control: control),
      ],
    );
  }
}

class _QuickControlCard extends StatelessWidget {
  const _QuickControlCard({required this.accent, required this.control});

  final Color accent;
  final QuickControl control;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final enabled = control.onChanged != null;

    return YaruBorderContainer(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(control.icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  control.title,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: enabled ? null : scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  control.subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          YaruSwitch(value: control.value, onChanged: control.onChanged),
        ],
      ),
    );
  }
}
