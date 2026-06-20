import 'package:flutter/material.dart';

import '../../../core/widgets/app_shell_components.dart';

/// One toggle in the dashboard [QuickControls] hub.
class QuickControl {
  const QuickControl({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;

  /// Null disables the toggle (unsupported, or an action is in flight).
  final ValueChanged<bool>? onChanged;
}

/// The dashboard quick-control hub: a single Yaru control card grouping the
/// most-used toggles (rapid charge, battery health, Fn lock, touchpad, …).
///
/// Decoupled from blocs — the page builds each [QuickControl] with its own
/// already-wired callback so this widget stays presentational.
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
    return AppControlCard(
      icon: Icons.tune,
      title: 'Quick controls',
      tint: accent,
      children: [
        for (final control in controls)
          AppSwitchTile(
            value: control.value,
            onChanged: control.onChanged,
            title: control.title,
            subtitle: control.subtitle,
          ),
      ],
    );
  }
}
