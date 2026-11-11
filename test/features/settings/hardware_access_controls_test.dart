import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/control_mode.dart';
import 'package:legion_frontend/core/providers/system_services_provider.dart';
import 'package:legion_frontend/features/settings/models/settings_snapshot.dart';
import 'package:legion_frontend/features/settings/providers/settings_provider.dart';
import 'package:legion_frontend/features/settings/repository/control_mode_store.dart';
import 'package:legion_frontend/features/settings/repository/settings_repository.dart';
import 'package:legion_frontend/features/settings/view/hardware_access_controls.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yaru/yaru.dart';

class Repository extends Mock implements SettingsRepository {}

class Store extends Mock implements ControlModeStore {}

void main() {
  const review = bool.fromEnvironment('CONTROL_MODE_REVIEW');
  setUpAll(() async {
    if (!review) return;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('yaru_window'),
      (call) async => call.method == 'state'
          ? {'active': true, 'visible': true, 'closable': true}
          : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('yaru_window/events'),
      (_) async => null,
    );
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in entry['fonts'] as List<dynamic>) {
        loader.addFont(
          rootBundle.load((font as Map<String, dynamic>)['asset'] as String),
        );
      }
      await loader.load();
    }
  });
  tearDownAll(() {
    if (!review) return;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('yaru_window'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('yaru_window/events'),
      null,
    );
  });
  for (final brightness in [Brightness.light, if (review) Brightness.dark]) {
    for (final compact in [false, true]) {
      testWidgets(
        'saves next-launch mode after confirmation (${brightness.name}, compact: $compact)',
        (tester) async {
          tester.view.physicalSize = compact
              ? const Size(420, 500)
              : const Size(900, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repository = Repository();
          when(
            repository.loadSnapshot,
          ).thenAnswer((_) async => const SettingsSnapshot(services: []));
          final store = Store();
          when(store.load).thenReturn(ControlMode.installedService);
          when(
            () => store.save(ControlMode.temporaryHelper),
          ).thenAnswer((_) async {});
          final container = ProviderContainer(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(repository),
              controlModeStoreProvider.overrideWithValue(store),
              portableControlAvailableProvider.overrideWithValue(true),
            ],
          );
          addTearDown(container.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: YaruTheme(
                data: const YaruThemeData(),
                builder: (context, yaru, _) => MaterialApp(
                  theme: yaru.theme,
                  darkTheme: yaru.darkTheme,
                  themeMode: brightness == Brightness.dark
                      ? ThemeMode.dark
                      : ThemeMode.light,
                  home: RepaintBoundary(
                    key: const ValueKey('capture'),
                    child: MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(compact ? 1.4 : 1),
                      ),
                      child: const Scaffold(
                        body: SingleChildScrollView(
                          padding: EdgeInsets.all(24),
                          child: HardwareAccessControls(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Temporary helper'));
          await tester.pumpAndSettle();
          expect(find.text('Use a temporary helper?'), findsOneWidget);
          await tester.ensureVisible(find.text('Cancel'));
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          verifyNever(() => store.save(ControlMode.temporaryHelper));
          await tester.tap(find.text('Temporary helper'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Use on next launch'));
          await tester.tap(find.text('Use on next launch'));
          await tester.pumpAndSettle();
          verify(() => store.save(ControlMode.temporaryHelper)).called(1);
          expect(
            container.read(controlModeProvider),
            ControlMode.installedService,
          );
          expect(
            find.textContaining('Reopen the app to use Temporary helper'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          if (review) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('capture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              image.dispose();
              await Directory(
                'build/control-mode-review',
              ).create(recursive: true);
              await File(
                'build/control-mode-review/${brightness.name}-${compact ? "compact" : "normal"}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
            });
          }
        },
      );
    }
  }
}
