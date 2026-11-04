import 'package:integration_test/integration_test.dart';

import 'scenarios/battery_health_journey.dart' as battery_health;
import 'scenarios/control_recovery_journey.dart' as control_recovery;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  battery_health.main();
  control_recovery.main();
}
