import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scenarios/battery_health_journey.dart' as battery_health;
import 'scenarios/control_recovery_journey.dart' as control_recovery;
import 'scenarios/keyboard_profile_journey.dart' as keyboard_profile;
import 'scenarios/keyboard_mode_journey.dart' as keyboard_mode;
import 'scenarios/keyboard_missing_profile_journey.dart' as keyboard_missing;
import 'scenarios/fans_preset_journey.dart' as fans_preset;
import 'scenarios/fan_curve_journey.dart' as fan_curve;
import 'scenarios/keyboard_recovery_journey.dart' as keyboard_recovery;
import 'scenarios/power_mode_journey.dart' as power_mode;
import 'scenarios/power_limits_journey.dart' as power_limits;
import 'scenarios/rapid_charging_journey.dart' as rapid_charging;
import 'scenarios/portable_channel_journey.dart' as portable_channel;
import 'scenarios/hardware_access_journey.dart' as hardware_access;
import 'scenarios/control_write_safety_journey.dart' as write_safety;
import 'scenarios/graphics_journey.dart' as graphics;
import 'scenarios/settings_diagnostics_journey.dart' as settings_diagnostics;
import 'scenarios/spectrum_lifecycle_journey.dart' as spectrum;
import 'scenarios/navigation_smoke_journey.dart' as navigation_smoke;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  battery_health.main();
  control_recovery.main();
  power_mode.main();
  power_limits.main();
  rapid_charging.main();
  keyboard_profile.main();
  keyboard_mode.main();
  keyboard_missing.main();
  fans_preset.main();
  fan_curve.main();
  keyboard_recovery.main();
  portable_channel.main();
  hardware_access.main();
  write_safety.main();
  graphics.main();
  settings_diagnostics.main();
  spectrum.main();
  navigation_smoke.main();
}
