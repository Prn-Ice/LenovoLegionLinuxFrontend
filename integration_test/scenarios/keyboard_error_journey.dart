import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';
import 'package:legion_frontend/features/automation/repository/automation_repository.dart';
import 'package:legion_frontend/features/lighting/bloc/rgb_lighting_state.dart';
import 'package:legion_frontend/features/lighting/providers/lighting_provider.dart';
import 'package:legion_frontend/features/lighting/view/lighting_page.dart';
import 'package:yaru/yaru.dart';

import '../support/journey.dart';
import '../support/keyboard_journey.dart';
import '../support/safe_app.dart';
import '../support/safe_lighting.dart';

void main() {
  testWidgets('deleted assigned profile is explained and can be cleared', (
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
    await paintKeyboard(tester, lighting, 'FF3311');
    await saveKeyboardProfile(tester, 'Recovery look');
    await openAutomation(tester);
    await assignKeyboardProfile(
      tester,
      KeyboardPowerMode.balanced,
      'Recovery look',
    );

    await openLighting(tester);
    final chip = find.ancestor(
      of: find.text('Recovery look'),
      matching: find.byType(InputChip),
    );
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: chip, matching: find.byIcon(YaruIcons.window_close)),
    );
    await waitFor(
      tester,
      () =>
          Hive.box<dynamic>('rgb_lighting').get('profile:Recovery look') ==
          null,
      description: 'profile deletion persisted through Lighting UI',
    );

    final writesBeforeClear = lighting.writes.length;
    await openAutomation(tester);
    await waitFor(
      tester,
      () => find
          .text(
            'This profile was deleted. Choose another profile or Leave unchanged.',
          )
          .evaluate()
          .isNotEmpty,
      description: 'missing assignment guidance in Automation',
    );
    expect(find.text('Recovery look (missing)'), findsOneWidget);
    await assignKeyboardProfile(tester, KeyboardPowerMode.balanced, null);
    final repository = AutomationRepository(
      configFile: File('${app.directory.path}/automation_rules.json'),
    );
    expect(
      (await repository.loadConfig()).profiles[KeyboardPowerMode.balanced],
      isNull,
    );
    await waitFor(
      tester,
      () => find
          .text(
            'This profile was deleted. Choose another profile or Leave unchanged.',
          )
          .evaluate()
          .isEmpty,
      description: 'cleared assignment removes missing-profile guidance',
    );
    expect(lighting.writes, hasLength(writesBeforeClear));
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed profile load keeps the confirmed look and can retry', (
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
    await paintKeyboard(tester, lighting, 'FF3311');
    await saveKeyboardProfile(tester, 'Profile A');
    await paintKeyboard(tester, lighting, '1133FF');
    final state = _rgbState(tester);
    expect(_hex(state), ['1133FF', '1133FF', '1133FF']);

    final writesBeforeFailure = lighting.writes.length;
    final requestsBeforeFailure = lighting.requests.length;
    final profileChip = find.widgetWithText(InputChip, 'Profile A');
    await tester.ensureVisible(profileChip);
    await tester.pumpAndSettle();
    lighting.nextFailure = OpenRgbFailure.applyRejected;
    await tester.tap(profileChip);
    await waitFor(
      tester,
      () => find.text('Action could not be completed').evaluate().isNotEmpty,
      description: 'profile-load failure dialog',
    );
    expect(
      find.textContaining('Could not apply keyboard profile "Profile A"'),
      findsOneWidget,
    );
    expect(lighting.requests, hasLength(requestsBeforeFailure + 1));
    expect(lighting.requests.last, ['FF3311', 'FF3311', 'FF3311']);
    expect(lighting.writes, hasLength(writesBeforeFailure));
    expect(_hex(_rgbState(tester)), ['1133FF', '1133FF', '1133FF']);
    final colorField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.prefixText == '#',
    );
    expect(tester.widget<TextField>(colorField).controller?.text, '1133FF');

    await tester.tap(find.text('Close').hitTestable());
    await waitFor(
      tester,
      () => find.text('Action could not be completed').evaluate().isEmpty,
      description: 'dismissed profile-load error dialog',
    );
    await tester.pumpAndSettle();
    final retryRequests = lighting.requests.length;
    await tester.tap(profileChip);
    await waitFor(
      tester,
      () =>
          lighting.writes.length == writesBeforeFailure + 1 &&
          tester.widget<TextField>(colorField).controller?.text == 'FF3311',
      description: 'successful retry applying Profile A',
    );
    expect(lighting.requests, hasLength(retryRequests + 1));
    expect(lighting.requests.last, ['FF3311', 'FF3311', 'FF3311']);
    expect(lighting.writes.last, ['FF3311', 'FF3311', 'FF3311']);
    expect(_hex(_rgbState(tester)), ['FF3311', 'FF3311', 'FF3311']);
    expect(tester.takeException(), isNull);
  });
}

RgbLightingState _rgbState(WidgetTester tester) {
  final context = tester.element(find.byType(LightingPage));
  return ProviderScope.containerOf(context).read(rgbLightingBlocProvider);
}

List<String> _hex(RgbLightingState state) => state.keyColors
    .map(
      (color) => color.toARGB32().toRadixString(16).substring(2).toUpperCase(),
    )
    .toList();
