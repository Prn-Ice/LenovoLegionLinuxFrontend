import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'scenarios/navigation_smoke_journey.dart' as navigation_smoke;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  navigation_smoke.main();
}
