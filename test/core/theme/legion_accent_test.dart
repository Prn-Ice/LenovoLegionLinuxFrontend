import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/theme/legion_accent.dart';

void main() {
  group('LegionAccent palette matches the handoff tokens', () {
    test('quiet', () {
      expect(LegionAccent.quiet.mode, LegionAccentMode.quiet);
      expect(LegionAccent.quiet.color, const Color(0xFF12A4B8));
      expect(LegionAccent.quiet.label, 'Quiet');
    });

    test('balanced', () {
      expect(LegionAccent.balanced.mode, LegionAccentMode.balanced);
      expect(LegionAccent.balanced.color, const Color(0xFF3A9D4F));
      expect(LegionAccent.balanced.label, 'Balanced');
    });

    test('performance', () {
      expect(LegionAccent.performance.mode, LegionAccentMode.performance);
      expect(LegionAccent.performance.color, const Color(0xFFEC5F2A));
      expect(LegionAccent.performance.label, 'Performance');
    });

    test('custom', () {
      expect(LegionAccent.custom.mode, LegionAccentMode.custom);
      expect(LegionAccent.custom.color, const Color(0xFF8056D6));
      expect(LegionAccent.custom.label, 'Custom');
    });
  });

  group('fromPowerModeValue', () {
    test('maps the three core platform profiles', () {
      expect(LegionAccent.fromPowerModeValue('quiet'), LegionAccent.quiet);
      expect(
        LegionAccent.fromPowerModeValue('balanced'),
        LegionAccent.balanced,
      );
      expect(
        LegionAccent.fromPowerModeValue('performance'),
        LegionAccent.performance,
      );
    });

    test('maps balanced-performance to custom (the app labels it Custom)', () {
      expect(
        LegionAccent.fromPowerModeValue('balanced-performance'),
        LegionAccent.custom,
      );
    });

    test(
      'returns null for unknown or null values so callers can fall back',
      () {
        expect(LegionAccent.fromPowerModeValue('turbo'), isNull);
        expect(LegionAccent.fromPowerModeValue(null), isNull);
      },
    );
  });

  group('soft / onSoft', () {
    const scheme = ColorScheme.light();

    test('soft blends the accent over the surface at the default alpha', () {
      expect(
        LegionAccent.performance.soft(scheme),
        Color.alphaBlend(
          const Color(0xFFEC5F2A).withValues(alpha: 0.14),
          scheme.surface,
        ),
      );
    });

    test('soft respects a custom alpha', () {
      expect(
        LegionAccent.performance.soft(scheme, alpha: 0.30),
        Color.alphaBlend(
          const Color(0xFFEC5F2A).withValues(alpha: 0.30),
          scheme.surface,
        ),
      );
    });

    test('soft is fully opaque (safe as a card background)', () {
      expect(LegionAccent.quiet.soft(scheme).a, 1.0);
    });

    test('onSoft returns the accent color', () {
      expect(LegionAccent.custom.onSoft(scheme), const Color(0xFF8056D6));
    });
  });
}
