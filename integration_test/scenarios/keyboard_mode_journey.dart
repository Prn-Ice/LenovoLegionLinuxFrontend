import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';
import 'package:legion_frontend/features/dashboard/providers/dashboard_provider.dart';
import 'package:legion_frontend/features/dashboard/view/dashboard_page.dart';

import '../support/journey.dart';
import '../support/keyboard_journey.dart';
import '../support/safe_app.dart';
import '../support/safe_lighting.dart';

void main() {
  testWidgets('observed power-mode changes apply assigned keyboard profiles', (
    tester,
  ) async {
    final app = await SafeApp.create();
    final lighting = SafeLighting(app);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });
    await app.launch(additionalOverrides: lighting.overrides);

    await openLighting(tester);
    _logCheckpoint('lighting opened');
    await paintKeyboard(tester, lighting, 'FF3311');
    await saveKeyboardProfile(tester, 'Journey Balanced');
    await paintKeyboard(tester, lighting, '1133FF');
    await saveKeyboardProfile(tester, 'Journey Performance');
    _logCheckpoint('profiles saved');

    await openAutomation(tester);
    final beforeBalancedAssignment = lighting.writes.length;
    await assignKeyboardProfile(
      tester,
      KeyboardPowerMode.balanced,
      'Journey Balanced',
    );
    await waitFor(
      tester,
      () => lighting.writes.length == beforeBalancedAssignment + 1,
      description: 'current Balanced profile applied when assigned',
    );
    _logCheckpoint('balanced assignment applied');
    expect(lighting.writes.last, ['FF3311', 'FF3311', 'FF3311']);

    final beforePerformanceAssignment = lighting.writes.length;
    await assignKeyboardProfile(
      tester,
      KeyboardPowerMode.performance,
      'Journey Performance',
    );
    expect(lighting.writes, hasLength(beforePerformanceAssignment));
    _logCheckpoint('performance assignment stored');

    // Dashboard refresh observes the sysfs value that Fn+Q changes externally.
    await openDashboard(tester);
    await _setObservedMode(app, FixturePlatformProfile.performance);
    await _refreshAndWaitForReload(tester, KeyboardPowerMode.performance);
    await waitFor(
      tester,
      () => lighting.writes.length == beforePerformanceAssignment + 1,
      description: 'Performance profile applied after leaving Automation',
    );
    _logCheckpoint('performance mode applied');
    expect(lighting.writes.last, ['1133FF', '1133FF', '1133FF']);

    final beforeUnrelatedRefresh = lighting.writes.length;
    await _refreshAndWaitForReload(tester, KeyboardPowerMode.performance);
    expect(lighting.writes, hasLength(beforeUnrelatedRefresh));
    _logCheckpoint('unrelated refresh preserved lighting');

    await openLighting(tester);
    await paintKeyboard(tester, lighting, '11CC44');
    final beforeSameModeRefresh = lighting.writes.length;
    await openDashboard(tester);
    await _refreshAndWaitForReload(tester, KeyboardPowerMode.performance);
    expect(lighting.writes, hasLength(beforeSameModeRefresh));
    _logCheckpoint('same mode refresh preserved edit');

    await _setObservedMode(app, FixturePlatformProfile.balanced);
    await _refreshAndWaitForReload(tester, KeyboardPowerMode.balanced);
    await waitFor(
      tester,
      () => lighting.writes.length == beforeSameModeRefresh + 1,
      description: 'Balanced profile reapplied after an observed mode change',
    );
    _logCheckpoint('balanced mode applied');
    expect(lighting.writes.last, ['FF3311', 'FF3311', 'FF3311']);
    final exception = tester.takeException();
    if (exception != null) {
      // ignore: avoid_print
      print(
        'KEYBOARD_MODE_UNEXPECTED_EXCEPTION: '
        '${exception.runtimeType}: $exception',
      );
    }
    expect(exception, isNull);
  });
}

// Keep checkpoints synchronous so a native runner cannot lose them behind the
// widget tree dump when this journey fails.
void _logCheckpoint(String message) {
  // ignore: avoid_print
  print('KEYBOARD_MODE_CHECKPOINT: $message');
}

Future<void> _setObservedMode(SafeApp app, FixturePlatformProfile mode) async {
  final file = File('${app.directory.path}/sys/firmware/acpi/platform_profile');
  final value = switch (mode) {
    FixturePlatformProfile.quiet => 'quiet',
    FixturePlatformProfile.balanced => 'balanced',
    FixturePlatformProfile.performance => 'performance',
    FixturePlatformProfile.maxPower => 'max-power',
  };
  final pending = File('${file.path}.pending');
  await pending.writeAsString('$value\n');
  await pending.rename(file.path);
}

Future<void> _refreshAndWaitForReload(
  WidgetTester tester,
  KeyboardPowerMode expectedMode,
) async {
  final context = tester.element(find.byType(DashboardPage));
  final dashboardBloc = ProviderScope.containerOf(context)
      .read(dashboardBlocProvider.bloc);
  final previousRead = dashboardBloc.state.snapshot.status.updatedAt;
  var reloadCompleted = false;
  // Refresh can share an in-flight poll. Require a fresh successful snapshot,
  // rather than a separate loading emission for the button press.
  final subscription = dashboardBloc.stream.listen((state) {
    if (!state.isLoading &&
        state.errorMessage == null &&
        state.snapshot.status.updatedAt != previousRead &&
        KeyboardPowerMode.fromPlatformProfile(
              state.snapshot.status.powerProfile,
            ) ==
            expectedMode) {
      reloadCompleted = true;
    }
  });
  try {
    await tester.tap(find.byTooltip('Refresh'));
    await waitFor(
      tester,
      () => reloadCompleted,
      description: 'fresh Dashboard snapshot with ${expectedMode.label} mode',
    );
    await _waitForDashboardMode(tester, expectedMode.label);
  } finally {
    await subscription.cancel();
  }
}

Future<void> _waitForDashboardMode(WidgetTester tester, String label) async {
  await waitFor(tester, () {
    final modeLabel = find.descendant(
      of: find.byType(DashboardPage),
      matching: find.text(label),
    );
    final chips = find.ancestor(
      of: modeLabel,
      matching: find.byType(ChoiceChip),
    );
    return chips.evaluate().any(
      (element) => (element.widget as ChoiceChip).selected,
    );
  }, description: 'Dashboard observed $label mode');
}
