import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/widgets/metric_format.dart';
import 'package:legion_frontend/core/widgets/metric_text.dart';

void main() {
  const scheme = ColorScheme.dark();

  test(
    'mono telemetry roles render in the Yaru-bundled Ubuntu Mono, not sans',
    () {
      final styles = <TextStyle>[
        monoStatValueStyle,
        monoGaugeStyle(116, scheme.onSurface),
        monoBarStyle(scheme.onSurface),
        monoUnitStyle(scheme),
        monoMetaStyle(scheme),
        monoFactStyle(scheme),
      ];

      for (final style in styles) {
        // Setting `package: 'yaru'` makes Flutter rewrite the family to
        // 'packages/yaru/UbuntuMono'; assert both halves so a dropped package
        // (which silently falls back to sans) fails the test.
        expect(style.fontFamily, contains(kMonoFontFamily));
        expect(style.fontFamily, contains(kMonoFontPackage));
      }
    },
  );
}
