import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/devices/models/devices_snapshot.dart';
import 'package:legion_frontend/features/devices/providers/devices_provider.dart';
import 'package:legion_frontend/features/devices/repository/devices_repository.dart';
import 'package:legion_frontend/features/devices/view/devices_page.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yaru/yaru.dart';

class MockDevicesPageRepository extends Mock implements DevicesRepository {}

void main() {
  for (final cameraEnabled in [true, false]) {
    testWidgets(
      'Devices keeps readable camera ${cameraEnabled ? 'on' : 'off'} read-only',
      (tester) async {
        final repository = MockDevicesPageRepository();
        when(repository.loadSnapshot).thenAnswer(
          (_) async => DevicesSnapshot(
            touchpadEnabled: true,
            touchpadSupported: true,
            winKeyEnabled: null,
            winKeySupported: false,
            fnLockEnabled: null,
            fnLockSupported: false,
            cameraEnabled: cameraEnabled,
            cameraSupported: true,
          ),
        );
        when(() => repository.setTouchpad(false)).thenAnswer((_) async {});
        final container = ProviderContainer.test(
          overrides: [devicesRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: Scaffold(body: DevicesPage())),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('${cameraEnabled ? 'Enabled' : 'Disabled'} (Read-only)'),
          findsOneWidget,
        );
        final cameraTile = tester.widget<YaruSwitchListTile>(
          find.widgetWithText(YaruSwitchListTile, 'Camera'),
        );
        expect(cameraTile.onChanged, isNull);
        verifyNever(() => repository.setCamera(any()));

        // A neighboring writable control remains actionable.
        await tester.tap(find.widgetWithText(YaruSwitchListTile, 'Touchpad'));
        await tester.pumpAndSettle();
        verify(() => repository.setTouchpad(false)).called(1);
        container.dispose();
      },
    );
  }

  testWidgets('Devices keeps absent camera unavailable', (tester) async {
    final repository = MockDevicesPageRepository();
    when(repository.loadSnapshot).thenAnswer(
      (_) async => const DevicesSnapshot(
        touchpadEnabled: null,
        touchpadSupported: false,
        winKeyEnabled: null,
        winKeySupported: false,
        fnLockEnabled: null,
        fnLockSupported: false,
        cameraEnabled: null,
        cameraSupported: false,
      ),
    );
    final container = ProviderContainer.test(
      overrides: [devicesRepositoryProvider.overrideWithValue(repository)],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DevicesPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not supported on this device'), findsWidgets);
    expect(find.textContaining('Read-only'), findsNothing);
    container.dispose();
  });
}
