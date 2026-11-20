import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/app/view/package_power_prompt.dart';
import 'package:legion_frontend/core/providers/system_services_provider.dart';
import 'package:legion_frontend/core/services/package_power_telemetry_service.dart';
import 'package:material_ui/material_ui.dart';

class _PowerClient implements PackagePowerTelemetryClient {
  int requests = 0;

  @override
  Future<void> enable() async => requests++;

  @override
  Future<double?> readPackagePowerWatts() async => null;
}

void main() {
  for (final choice in ['Skip', 'Allow']) {
    testWidgets('opens the dashboard after choosing $choice', (tester) async {
      final client = _PowerClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            packagePowerTelemetryClientProvider.overrideWithValue(client),
          ],
          child: const MaterialApp(
            home: PackagePowerPrompt(child: Text('Dashboard')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Show CPU power usage?'), findsOneWidget);
      expect(client.requests, 0);
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      expect(find.text('Show CPU power usage?'), findsNothing);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(client.requests, choice == 'Allow' ? 1 : 0);
    });
  }
}
