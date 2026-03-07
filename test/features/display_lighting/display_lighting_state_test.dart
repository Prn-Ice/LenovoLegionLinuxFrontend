import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/display_lighting/bloc/display_lighting_state.dart';

void main() {
  group('DisplayLightingState refresh rate fields', () {
    test('initial state has all refresh rate fields as null', () {
      final state = DisplayLightingState.initial();
      expect(state.xrandrOutputName, isNull);
      expect(state.availableRefreshRates, isNull);
      expect(state.currentRefreshRate, isNull);
    });

    test('copyWith sets xrandrOutputName', () {
      final state = DisplayLightingState.initial().copyWith(
        xrandrOutputName: 'eDP-1',
      );
      expect(state.xrandrOutputName, equals('eDP-1'));
    });

    test('copyWith sets availableRefreshRates', () {
      final rates = [60.0, 120.0, 144.0];
      final state = DisplayLightingState.initial().copyWith(
        availableRefreshRates: rates,
      );
      expect(state.availableRefreshRates, equals(rates));
    });

    test('copyWith sets currentRefreshRate', () {
      final state = DisplayLightingState.initial().copyWith(
        currentRefreshRate: 144.0,
      );
      expect(state.currentRefreshRate, equals(144.0));
    });

    test('copyWith with no refresh rate args preserves existing values', () {
      final rates = [60.0, 120.0];
      final base = DisplayLightingState.initial().copyWith(
        xrandrOutputName: 'eDP-1',
        availableRefreshRates: rates,
        currentRefreshRate: 60.0,
      );
      final updated = base.copyWith(isLoading: false);
      expect(updated.xrandrOutputName, equals('eDP-1'));
      expect(updated.availableRefreshRates, equals(rates));
      expect(updated.currentRefreshRate, equals(60.0));
    });

    test('copyWith can reset refresh rate fields to null', () {
      final base = DisplayLightingState.initial().copyWith(
        xrandrOutputName: 'eDP-1',
        currentRefreshRate: 60.0,
      );
      final reset = base.copyWith(
        xrandrOutputName: null,
        currentRefreshRate: null,
      );
      expect(reset.xrandrOutputName, isNull);
      expect(reset.currentRefreshRate, isNull);
    });

    test('props distinguishes different currentRefreshRate', () {
      final s1 = DisplayLightingState.initial().copyWith(
        currentRefreshRate: 60.0,
      );
      final s2 = DisplayLightingState.initial().copyWith(
        currentRefreshRate: 144.0,
      );
      expect(s1, isNot(equals(s2)));
    });
  });
}
