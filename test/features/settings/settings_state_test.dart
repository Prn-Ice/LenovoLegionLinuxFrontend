import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/settings/bloc/settings_state.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('appearance defaults follow the system', () {
    final state = SettingsState.initial();
    expect(state.themeMode, ThemeMode.system);
    expect(state.yaruVariant, isNull);
    expect(state.accentFollowsPowerMode, isFalse);
    expect(state.appearanceErrorMessage, isNull);
  });

  test('copying preserves or explicitly clears the appearance failure', () {
    final state = SettingsState.initial().copyWith(
      appearanceErrorMessage: 'disk full',
    );
    expect(
      state.copyWith(themeMode: ThemeMode.dark).appearanceErrorMessage,
      'disk full',
    );
    expect(
      state.copyWith(appearanceErrorMessage: null).appearanceErrorMessage,
      isNull,
    );
    expect(state.copyWith(), state);
    expect(state.copyWith(themeMode: ThemeMode.dark), isNot(state));
  });
}
