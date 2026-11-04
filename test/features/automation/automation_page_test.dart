import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';
import 'package:legion_frontend/features/automation/providers/automation_provider.dart';
import 'package:legion_frontend/features/automation/view/automation_page.dart';
import 'package:legion_frontend/features/dashboard/providers/dashboard_provider.dart';
import 'package:legion_frontend/features/lighting/providers/lighting_provider.dart';

import '../../support/keyboard_automation_fakes.dart';

void main() {
  late MemoryAssignments assignments;
  late MemoryLightingProfiles profiles;
  setUp(() {
    assignments = MemoryAssignments();
    profiles = MemoryLightingProfiles();
  });
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          automationRepositoryProvider.overrideWithValue(assignments),
          dashboardRepositoryProvider.overrideWithValue(ObservedPowerMode()),
          rgbLightingRepositoryProvider.overrideWithValue(RecordingKeyboard()),
          spectrumRgbRepositoryProvider.overrideWithValue(NoNativeKeyboard()),
          rgbLightingStoreProvider.overrideWithValue(profiles),
        ],
        child: const MaterialApp(home: Scaffold(body: AutomationPage())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'assigns and clears a named profile with the production provider',
    (tester) async {
      await pumpPage(tester);
      expect(find.text('Keyboard profiles by power mode'), findsOneWidget);
      expect(find.text('Current mode: Balanced'), findsOneWidget);
      final quiet = find.byType(DropdownButtonFormField<String>).first;
      await tester.ensureVisible(quiet);
      await tester.pumpAndSettle();
      await tester.tap(quiet);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Night').last);
      await tester.pumpAndSettle();
      expect(assignments.config.profiles[KeyboardPowerMode.quiet], 'Night');
      await tester.tap(quiet);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave unchanged').last);
      await tester.pumpAndSettle();
      expect(assignments.config.profiles, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'empty and deleted profiles have actionable guidance at compact size',
    (tester) async {
      tester.view.physicalSize = const Size(420, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      profiles.profiles.clear();
      assignments.config = assignments.config.assign(
        KeyboardPowerMode.quiet,
        'Deleted',
      );
      await pumpPage(tester);
      expect(find.text('Deleted (missing)'), findsOneWidget);
      expect(find.textContaining('This profile was deleted'), findsOneWidget);
      await tester.ensureVisible(find.text('Manage lighting profiles'));
      await tester.pumpAndSettle();
      expect(
        find.text('Manage lighting profiles').hitTestable(),
        findsOneWidget,
      );
      expect(
        find.textContaining('Save a named profile in Lighting'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
