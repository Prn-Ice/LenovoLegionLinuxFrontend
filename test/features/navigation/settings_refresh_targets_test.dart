import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/navigation/models/settings_refresh_targets.dart';

void main() {
  test('a busy migrated feature is skipped independently', () {
    final targets = SettingsRefreshTargets.fromBusyStates(
      settingsLoading: false,
      settingsApplying: false,
      bootLogoLoading: true,
      bootLogoApplying: false,
      aboutLoading: false,
      devicesLoading: false,
      devicesApplying: true,
      displayLoading: false,
      displayApplying: false,
    );

    expect(targets.settings, isTrue);
    expect(targets.bootLogo, isFalse);
    expect(targets.about, isTrue);
    expect(targets.devices, isFalse);
    expect(targets.display, isTrue);
    expect(targets.canRefresh, isTrue);
  });

  test('refresh is disabled when every feature is busy', () {
    final targets = SettingsRefreshTargets.fromBusyStates(
      settingsLoading: true,
      settingsApplying: false,
      bootLogoLoading: false,
      bootLogoApplying: true,
      aboutLoading: true,
      devicesLoading: true,
      devicesApplying: false,
      displayLoading: false,
      displayApplying: true,
    );

    expect(targets.canRefresh, isFalse);
  });
}
