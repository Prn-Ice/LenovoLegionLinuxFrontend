import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/sysfs_probe.dart';
import 'package:legion_frontend/features/about/models/about_diagnostic_item.dart';
import 'package:legion_frontend/features/about/models/about_snapshot.dart';
import 'package:legion_frontend/features/about/providers/about_provider.dart';
import 'package:legion_frontend/features/about/repository/about_repository.dart';
import 'package:legion_frontend/features/analytics/models/sensor_record.dart';
import 'package:legion_frontend/features/analytics/providers/analytics_provider.dart';
import 'package:legion_frontend/features/analytics/repository/analytics_repository.dart';
import 'package:legion_frontend/features/diagnostics/view/diagnostics_page.dart';
import 'package:legion_frontend/features/lighting/models/spectrum_hid_discovery.dart';
import 'package:legion_frontend/features/lighting/models/spectrum_keyboard_profile.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yaru/yaru.dart';

class _AboutRepository extends Mock implements AboutRepository {}

class _AnalyticsRepository extends Mock implements AnalyticsRepository {}

void main() {
  const visualReview = bool.fromEnvironment('VISUAL_REVIEW');
  setUpAll(() async {
    if (!visualReview) return;
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in entry['fonts'] as List) {
        loader.addFont(rootBundle.load((font as Map)['asset'] as String));
      }
      await loader.load();
    }
  });
  for (final width in [420.0, 1000.0]) {
    testWidgets('report copy and file results remain usable at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      for (final channel in ['yaru_window', 'yaru_window/events']) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel(channel),
          (call) async => <String, Object?>{},
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            MethodChannel(channel),
            null,
          ),
        );
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final about = _AboutRepository();
      final analytics = _AnalyticsRepository();
      final snapshot = AboutSnapshot(
        updatedAt: DateTime(2026),
        cliPath: '/private/user/legion_cli',
        cliPathExists: false,
        pythonAvailable: false,
        controlServiceActive: false,
        systemctlAvailable: false,
        cliHealthy: false,
        cliHealthSummary: 'Unavailable',
        hardwareModel:
            'Synthetic model with a long descriptive family identifier',
        biosVersion: 'FIXTURE-BIOS',
        kernelVersion: null,
        moduleVersion: null,
        cliVersion: null,
        commandHistory: const [],
        spectrumHid: const SpectrumHidDiscovery(
          outcome: SpectrumHidDiscoveryOutcome.supported,
          vendorId: 0x048d,
          productId: 0xc987,
          selectedHidrawPath:
              '/private/user/long-fixture-directory/dev/hidraw5',
          profile: kSpectrumC987Profile,
        ),
        diagnostics: [
          AboutDiagnosticItem.fromProbe(
            id: 'battery_conservation',
            label: 'Battery conservation',
            frontendWriteAvailable: true,
            probe: const SysfsProbe([
              SysfsRead(
                path:
                    '/sys/bus/platform/drivers/ideapad_acpi/VPC2004:01/conservation_mode',
                outcome: SysfsReadOutcome.malformed,
              ),
            ]),
          ),
        ],
      );
      when(about.loadSnapshot).thenAnswer((_) async => snapshot);
      when(analytics.pruneOldRecords).thenAnswer((_) async {});
      when(
        () => analytics.readHistory(since: any(named: 'since')),
      ).thenReturn([]);
      when(
        analytics.recordReading,
      ).thenAnswer((_) async => SensorRecord(timestamp: DateTime(2026)));
      String? copied;
      var clipboardFails = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            if (clipboardFails) {
              throw PlatformException(code: 'clipboard-unavailable');
            }
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          aboutRepositoryProvider.overrideWithValue(about),
          analyticsRepositoryProvider.overrideWithValue(analytics),
        ],
      );
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              theme: yaruLight,
              home: const Scaffold(body: DiagnosticsPage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final copy = find.text('Copy report JSON');
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(jsonDecode(copied!), snapshot.toJson());
      expect(copied, isNot(contains('/private/user')));
      expect(find.text('Copied'), findsOneWidget);
      clipboardFails = true;
      await tester.ensureVisible(find.text('Copied'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copied'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not copy diagnostics'), findsWidgets);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Copy report JSON'), findsOneWidget);
      await tester.ensureVisible(find.text('Invalid value'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The app has a write control'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Keyboard profile found'));
      await tester.pumpAndSettle();
      expect(find.text('0x048d:0xc987'), findsOneWidget);
      expect(find.text('Spectrum / gen7And8'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (visualReview) {
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final file = File(
            'build/visual-review/diagnostics-${width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump();
    });
  }
}
