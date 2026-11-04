import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scenarios/battery_health_journey.dart' as battery_health;
import 'scenarios/control_recovery_journey.dart' as control_recovery;
import 'scenarios/keyboard_profile_journey.dart' as keyboard_profile;
import 'scenarios/keyboard_mode_journey.dart' as keyboard_mode;
import 'scenarios/keyboard_error_journey.dart' as keyboard_error;
import 'scenarios/fans_preset_journey.dart' as fans_preset;
import 'scenarios/power_mode_journey.dart' as power_mode;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  battery_health.main();
  control_recovery.main();
  power_mode.main();
  keyboard_profile.main();
  keyboard_mode.main();
  keyboard_error.main();
  fans_preset.main();
}
