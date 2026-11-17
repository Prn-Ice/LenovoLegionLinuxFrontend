import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/providers/system_services_provider.dart';
import 'package:legion_frontend/features/settings/view/hardware_access_controls.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final helperExists in [true, false]) {
    for (final width in [420.0, 900.0]) {
      testWidgets(
        'helper status and limits at $width pixels, file exists: $helperExists',
        (tester) async {
          tester.view.physicalSize = Size(width, 600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                bundledHelperExistsProvider.overrideWithValue(helperExists),
                legionControlClientProvider.overrideWith((_) {
                  fail('Settings must not request privileged access');
                }),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: MediaQuery(
                    data: const MediaQueryData(
                      textScaler: TextScaler.linear(1.5),
                    ),
                    child: const SingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: HardwareAccessControls(),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.textContaining(
              helperExists
                  ? 'first change a hardware setting'
                  : 'Reinstall a complete app build',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('15 minutes'), findsOneWidget);
          expect(
            find.textContaining('cannot manage background services'),
            findsOneWidget,
          );
          expect(find.byType(ChoiceChip), findsNothing);
          expect(find.textContaining('Installed service'), findsNothing);
          expect(find.textContaining('next launch'), findsNothing);
          await tester.ensureVisible(find.text('Other hardware permissions'));
          await tester.tap(find.text('Other hardware permissions'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Keyboard lighting and CPU power readings'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
