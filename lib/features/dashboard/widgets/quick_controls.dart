import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/responsive_card_grid.dart';
import '../../../core/widgets/surface_card.dart';

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
    final enabled = control.onChanged != null;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(control.icon, color: accent, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  control.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: enabled ? null : scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  control.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.56),
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
