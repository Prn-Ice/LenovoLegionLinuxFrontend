import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scenarios/battery_health_journey.dart' as battery_health;
import 'scenarios/control_recovery_journey.dart' as control_recovery;
import 'scenarios/keyboard_profile_journey.dart' as keyboard_profile;
import 'scenarios/keyboard_mode_journey.dart' as keyboard_mode;
import 'scenarios/keyboard_recovery_journey.dart' as keyboard_recovery;
import 'scenarios/power_mode_journey.dart' as power_mode;
import 'scenarios/portable_channel_journey.dart' as portable_channel;
import 'scenarios/control_mode_journey.dart' as control_mode;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  battery_health.main();
  control_recovery.main();
  power_mode.main();
  keyboard_profile.main();
  keyboard_mode.main();
  keyboard_recovery.main();
  portable_channel.main();
  control_mode.main();
}
