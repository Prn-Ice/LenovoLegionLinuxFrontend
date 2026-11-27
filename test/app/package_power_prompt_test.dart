import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:legion_frontend/app/view/package_power_prompt.dart';
import 'package:legion_frontend/core/providers/system_services_provider.dart';
import 'package:legion_frontend/core/services/package_power_telemetry_service.dart';
import 'package:legion_frontend/features/sensors/bloc/package_power_cubit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yaru/yaru.dart';

class _PowerClient implements PackagePowerTelemetryClient {
  int requests = 0;

  @override
  Future<void> enable() async => requests++;

  @override
  Future<void> disable() async {}

  @override
  Future<double?> readPackagePowerWatts() async => null;
}

void main() {
  late Box<dynamic> preferences;
  late Future<void> promptClosed;

  setUp(() async {
    final directory = await Directory.systemTemp.createTemp('power-prompt-');
    addTearDown(() => directory.delete(recursive: true));
    addTearDown(Hive.close);
    Hive.init(directory.path);
    preferences = await Hive.openBox<dynamic>('preferences');
  });

  Future<void> launch(WidgetTester tester, _PowerClient client) async {
    for (final channel in ['yaru_window', 'yaru_window/events']) {
      final messenger = tester.binding.defaultBinaryMessenger;
      final methodChannel = MethodChannel(channel);
      messenger.setMockMethodCallHandler(methodChannel, (_) async => {});
      addTearDown(
        () => messenger.setMockMethodCallHandler(methodChannel, null),
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          packagePowerTelemetryClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => promptClosed = requestPackagePowerAccess(
                context,
                ref,
                preferences: preferences,
              ),
              child: const Text('Dashboard'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => tester.tap(find.text('Dashboard')));
    await tester.pumpAndSettle();
  }

  final prompt = find.text('Show CPU power usage?');
  final checkbox = find.byType(YaruCheckButton);

  for (final allow in [false, true]) {
    final choice = allow ? 'Allow' : 'Skip';
    for (final hide in [false, true]) {
      testWidgets(
        '$choice ${hide ? 'hides' : 'keeps'} the prompt on the next launch',
        (tester) async {
          final client = _PowerClient();
          await launch(tester, client);
          expect(prompt, findsOneWidget);
          expect(client.requests, 0);
          expect(tester.widget<YaruCheckButton>(checkbox).value, isFalse);
          if (hide) {
            await tester.tap(find.text('Don’t show again'));
            await tester.pumpAndSettle();
            expect(tester.widget<YaruCheckButton>(checkbox).value, isTrue);
          }

          await tester.tap(find.text(choice));
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await promptClosed;
            await preferences.close();
            preferences = await Hive.openBox<dynamic>('preferences');
          });
          await tester.pumpAndSettle();
          expect(prompt, findsNothing);
          expect(client.requests, allow ? 1 : 0);
          final container = ProviderScope.containerOf(
            tester.element(find.text('Dashboard')),
          );
          expect(
            container.read(packagePowerProvider),
            allow ? PackagePowerState.on : PackagePowerState.off,
          );

          await tester.pumpWidget(const SizedBox.shrink());
          final nextClient = _PowerClient();
          await launch(tester, nextClient);
          expect(prompt, hide ? findsNothing : findsOneWidget);
          expect(nextClient.requests, 0);
        },
      );
    }
  }

  testWidgets('Escape dismisses the prompt without saving the checkbox', (
    tester,
  ) async {
    final client = _PowerClient();
    await launch(tester, client);
    await tester.tap(find.text('Don’t show again'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(prompt, findsNothing);
    expect(client.requests, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    final nextClient = _PowerClient();
    await launch(tester, nextClient);
    expect(prompt, findsOneWidget);
    expect(tester.widget<YaruCheckButton>(checkbox).value, isFalse);
    expect(nextClient.requests, 0);
  });
}
