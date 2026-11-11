import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/app_failure.dart';
import 'package:legion_frontend/core/widgets/app_shell_components.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';
import 'package:legion_frontend/features/automation/view/automation_page.dart';
import 'package:legion_frontend/features/lighting/providers/lighting_provider.dart';
import 'package:legion_frontend/features/lighting/view/lighting_page.dart';

import '../support/journey.dart';
import '../support/keyboard_journey.dart';
import '../support/safe_app.dart';
import '../support/safe_lighting.dart';

enum _RecoveryPage { lighting, automation }

void main() {
  for (final page in _RecoveryPage.values) {
    testWidgets(
      '${page.name} shows OpenRGB exit failures and supports profile retry',
      (tester) async {
        final app = await SafeApp.create();
        final lighting = SafeLighting(app);
        addTearDown(() async {
          final pending = lighting.writeCompletion;
          if (pending != null && !pending.isCompleted) pending.complete();
          await tester.pumpWidget(const SizedBox.shrink());
          await app.dispose();
        });
        await app.launch(additionalOverrides: lighting.overrides);
        await openLighting(tester);
        await paintKeyboard(tester, lighting, 'FF3311');
        await saveKeyboardProfile(tester, 'Recovery look');
        await paintKeyboard(tester, lighting, '1133FF');
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(LightingPage)),
        );
        final previous = container.read(rgbLightingBlocProvider);
        final store = container.read(rgbLightingStoreProvider);
        final previousSaved = store.load()!.toMap();
        final namedProfile = store.loadProfile('Recovery look')!.toMap();
        final writesBefore = lighting.writes.length;
        final requestsBefore = lighting.requests.length;

        lighting.nextExitCode = 17;
        if (page == _RecoveryPage.automation) {
          await openAutomation(tester);
          await assignKeyboardProfile(
            tester,
            KeyboardPowerMode.balanced,
            'Recovery look',
          );
        } else {
          await _applyProfile(tester, page);
        }
        await _expectFailure(tester);
        expect(
          container.read(rgbLightingBlocProvider).keyColors,
          previous.keyColors,
        );
        expect(store.load()!.toMap(), previousSaved);
        expect(store.loadProfile('Recovery look')!.toMap(), namedProfile);
        expect(lighting.writes, hasLength(writesBefore));
        expect(lighting.requests, hasLength(requestsBefore + 1));

        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(AppErrorDialog), findsNothing);
        // Retrying the same failed command must show a fresh dialog.
        lighting.nextExitCode = 17;
        await _applyProfile(tester, page);
        await _expectFailure(tester);
        expect(lighting.requests, hasLength(requestsBefore + 2));
        expect(store.load()!.toMap(), previousSaved);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        final pending = lighting.writeCompletion = Completer<void>();
        await _applyProfile(tester, page);
        await waitFor(
          tester,
          () => lighting.requests.length == requestsBefore + 3,
          description: 'pending OpenRGB profile command',
        );
        await tester.pumpAndSettle();
        expect(container.read(rgbLightingBlocProvider).isApplying, isTrue);
        expect(
          container.read(rgbLightingBlocProvider).keyColors,
          previous.keyColors,
        );
        expect(store.load()!.toMap(), previousSaved);
        expect(lighting.writes, hasLength(writesBefore));
        if (page == _RecoveryPage.automation) {
          expect(
            tester.widget<OutlinedButton>(_profileAction(page)).onPressed,
            isNull,
          );
          expect(find.byType(AutomationPage), findsOneWidget);
        } else {
          expect(
            tester.widget<InputChip>(_profileAction(page)).onPressed,
            isNull,
          );
        }

        pending.complete();
        await waitFor(tester, () {
          final state = container.read(rgbLightingBlocProvider);
          return !state.isApplying &&
              state.errorMessage == null &&
              state.keyColors.every(
                (color) => color == const Color(0xFFFF3311),
              );
        }, description: 'successful profile retry');
        await tester.pumpAndSettle();
        expect(lighting.writes, hasLength(writesBefore + 1));
        expect(lighting.writes.last, ['FF3311', 'FF3311', 'FF3311']);
        expect(store.load()!.toMap(), namedProfile);
        expect(find.byType(AppErrorDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Finder _profileAction(_RecoveryPage page) => page == _RecoveryPage.automation
    ? find.widgetWithText(OutlinedButton, 'Apply current profile')
    : find.widgetWithText(InputChip, 'Recovery look');

Future<void> _applyProfile(WidgetTester tester, _RecoveryPage page) async {
  final action = _profileAction(page);
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
}

Future<void> _expectFailure(WidgetTester tester) async {
  await waitFor(
    tester,
    () => find.byType(AppErrorDialog).evaluate().isNotEmpty,
    description: 'OpenRGB failure dialog',
  );
  await tester.pumpAndSettle();
  expect(find.byType(AppErrorDialog), findsOneWidget);
  final failure = AppFailure.from(
    tester.widget<AppErrorDialog>(find.byType(AppErrorDialog)).message,
  );
  expect(failure.kind, AppFailureKind.commandFailed);
  expect(failure.message, contains('Recovery look'));
  expect(failure.details, contains('Exit code: 17'));
  expect(failure.details, contains('Test device rejected the write'));
}
