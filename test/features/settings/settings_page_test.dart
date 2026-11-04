import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/app_failure.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/features/about/repository/about_repository.dart';
import 'package:legion_frontend/features/about/providers/about_provider.dart';
import 'package:legion_frontend/features/boot_logo/models/boot_logo_snapshot.dart';
import 'package:legion_frontend/features/boot_logo/models/boot_logo_status.dart';
import 'package:legion_frontend/features/boot_logo/providers/boot_logo_provider.dart';
import 'package:legion_frontend/features/boot_logo/repository/boot_logo_repository.dart';
import 'package:legion_frontend/features/devices/models/devices_snapshot.dart';
import 'package:legion_frontend/features/devices/providers/devices_provider.dart';
import 'package:legion_frontend/features/devices/repository/devices_repository.dart';
import 'package:legion_frontend/features/display/models/display_snapshot.dart';
import 'package:legion_frontend/features/display/providers/display_provider.dart';
import 'package:legion_frontend/features/display/repository/display_repository.dart';
import 'package:legion_frontend/features/settings/models/service_control.dart';
import 'package:legion_frontend/features/settings/bloc/settings_event.dart';
import 'package:yaru/yaru.dart';
import 'package:legion_frontend/features/settings/models/settings_snapshot.dart';
import 'package:legion_frontend/features/settings/providers/settings_provider.dart';
import 'package:legion_frontend/features/settings/repository/settings_repository.dart';
import 'package:legion_frontend/features/settings/view/settings_page.dart';
import 'package:mocktail/mocktail.dart';

import '../boot_logo/boot_logo_page_test.dart'
    show ControlledPicker, MockPlatformFile;

class SettingsRepo extends Mock implements SettingsRepository {}

class BootRepo extends Mock implements BootLogoRepository {}

class AboutRepo extends Mock implements AboutRepository {}

class DevicesRepo extends Mock implements DevicesRepository {}

class DisplayRepo extends Mock implements DisplayRepository {}

void main() {
  const service = ServiceControl(
    service: ControlService.legiondStack,
    label: 'Test service',
    units: ['test'],
    supported: true,
    active: true,
    enabled: true,
  );
  for (final scenario in [
    'picker',
    'boot logo',
    'win key',
    'win key unavailable',
    'appearance',
  ]) {
    testWidgets('Settings $scenario uses the current provider', (tester) async {
      if (scenario == 'appearance' || scenario == 'boot logo') {
        tester.view.physicalSize = const Size(420, 500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      final settings = SettingsRepo();
      when(
        settings.loadSnapshot,
      ).thenAnswer((_) async => const SettingsSnapshot(services: [service]));
      final boot = BootRepo();
      final nextBoot = BootRepo();
      const logo = BootLogoSnapshot(
        status: BootLogoStatus(
          isCustomEnabled: true,
          requiredWidth: 0,
          requiredHeight: 0,
        ),
      );
      for (final repo in [boot, nextBoot]) {
        when(repo.loadSnapshot).thenAnswer((_) async => logo);
      }
      when(() => boot.enableBootLogo('/tmp/logo.png')).thenThrow(
        const BootLogoRepositoryException(
          'Could not apply boot logo',
          kind: AppFailureKind.privilegeSetup,
          details: 'Test service unavailable',
        ),
      );
      when(boot.restoreBootLogo).thenAnswer((_) async {});
      final about = AboutRepo();
      when(about.loadSnapshot).thenThrow(Exception('unavailable'));
      final devices = DevicesRepo();
      final nextDevices = DevicesRepo();
      const deviceSnapshot = DevicesSnapshot(
        touchpadEnabled: null,
        touchpadSupported: false,
        winKeyEnabled: true,
        winKeySupported: true,
        fnLockEnabled: null,
        fnLockSupported: false,
        cameraEnabled: true,
        cameraSupported: true,
      );
      for (final repo in [devices, nextDevices]) {
        when(repo.loadSnapshot).thenAnswer((_) async => deviceSnapshot);
        when(() => repo.setWinKey(false)).thenAnswer((_) async {});
      }
      if (scenario == 'win key unavailable') {
        when(nextDevices.loadSnapshot).thenAnswer(
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
      }
      final display = DisplayRepo();
      when(display.loadSnapshot).thenAnswer(
        (_) async => const DisplaySnapshot(
          overdriveEnabled: false,
          overdriveSupported: true,
          xrandrOutputName: 'eDP-1',
          availableRefreshRates: [60, 144],
          currentRefreshRate: 60,
        ),
      );
      overrides(BootRepo logoRepo, DevicesRepo deviceRepo) => [
        settingsRepositoryProvider.overrideWithValue(settings),
        bootLogoRepositoryProvider.overrideWithValue(logoRepo),
        aboutRepositoryProvider.overrideWithValue(about),
        devicesRepositoryProvider.overrideWithValue(deviceRepo),
        displayRepositoryProvider.overrideWithValue(display),
      ];
      final originalPicker = FilePickerPlatform.instance;
      final picker = ControlledPicker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = originalPicker);
      final container = ProviderContainer.test(
        overrides: overrides(boot, devices),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SettingsPage())),
        ),
      );
      await tester.pumpAndSettle();
      if (find.text('Close').evaluate().isNotEmpty) {
        await tester.tap(find.text('Close').last);
        await tester.pumpAndSettle();
      }
      for (final label in [
        'Appearance',
        'Backend',
        'Boot Logo',
        'Win Key',
        'Camera',
        'Overdrive',
        'Refresh Rate',
        'About',
      ]) {
        expect(find.text(label), findsWidgets);
      }
      if (scenario == 'appearance') {
        container
            .read(settingsBlocProvider.bloc)
            .add(const YaruVariantChanged(YaruVariant.blue));
        await tester.pumpAndSettle();
        final follow = find.text('Follow power mode accent');
        await tester.ensureVisible(follow);
        await tester.pumpAndSettle();
        await tester.tap(follow);
        await tester.pumpAndSettle();
        expect(
          container.read(settingsBlocProvider).accentFollowsPowerMode,
          isTrue,
        );
        expect(find.textContaining('Manual accent is saved'), findsOneWidget);
        final system = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'System accent'),
        );
        expect(system.onSelected, isNull);
        final blue = find.bySemanticsLabel('blue accent colour');
        expect(blue, findsOneWidget);
        await tester.ensureVisible(blue);
        await tester.pumpAndSettle();
        await tester.tap(blue);
        await tester.pumpAndSettle();
        expect(
          container.read(settingsBlocProvider).yaruVariant,
          YaruVariant.blue,
        );
        await tester.ensureVisible(follow);
        await tester.pumpAndSettle();
        await tester.tap(follow);
        await tester.pumpAndSettle();
        expect(
          container.read(settingsBlocProvider).accentFollowsPowerMode,
          isFalse,
        );
        expect(
          container.read(settingsBlocProvider).yaruVariant,
          YaruVariant.blue,
        );
        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, 'System accent'),
              )
              .onSelected,
          isNotNull,
        );
      } else if (scenario == 'boot logo') {
        await tester.ensureVisible(find.text('Browse...'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Browse...'));
        picker.result.complete([MockPlatformFile()]);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('Clear selection'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Clear selection'));
        await tester.pumpAndSettle();
        expect(find.text('No image selected'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Apply Custom Logo'),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('Browse...'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Apply Custom Logo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply Custom Logo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        verifyNever(() => boot.enableBootLogo('/tmp/logo.png'));
        await tester.tap(find.text('Apply Custom Logo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply').last);
        await tester.pumpAndSettle();
        verify(() => boot.enableBootLogo('/tmp/logo.png')).called(1);
        expect(find.text('Privileged access needs setup'), findsOneWidget);
        expect(
          container.read(bootLogoBlocProvider).errorMessage?.kind,
          AppFailureKind.privilegeSetup,
        );
        expect(
          container.read(bootLogoBlocProvider).errorMessage?.details,
          'Test service unavailable',
        );
        await tester.tap(find.text('Close').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Restore Default'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restore Default'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        verifyNever(boot.restoreBootLogo);
        await tester.tap(find.text('Restore Default'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restore').last);
        await tester.pumpAndSettle();
        verify(boot.restoreBootLogo).called(1);
      } else if (scenario == 'picker') {
        await tester.ensureVisible(find.text('Browse...'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Browse...'));
        await tester.pump();
        final old = container.read(bootLogoBlocProvider.bloc);
        container.updateOverrides(overrides(nextBoot, devices));
        await tester.pumpAndSettle();
        expect(old.isClosed, isTrue);
        picker.result.complete([MockPlatformFile()]);
        await tester.pumpAndSettle();
        expect(
          container.read(bootLogoBlocProvider).selectedImagePath,
          '/tmp/logo.png',
        );
      } else {
        await tester.ensureVisible(find.text('Win Key'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Win Key'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        verifyNever(() => devices.setWinKey(false));
        await tester.tap(find.text('Win Key'));
        await tester.pumpAndSettle();
        final old = container.read(devicesBlocProvider.bloc);
        container.updateOverrides(overrides(boot, nextDevices));
        await tester.pumpAndSettle();
        expect(old.isClosed, isTrue);
        await tester.tap(find.text('Apply').last);
        await tester.pumpAndSettle();
        verifyNever(() => devices.setWinKey(false));
        if (scenario == 'win key unavailable') {
          verifyNever(() => nextDevices.setWinKey(false));
        } else {
          verify(() => nextDevices.setWinKey(false)).called(1);
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      container.dispose();
      await tester.pump();
    });
  }
  for (final disposeDuringConfirmation in [false, true]) {
    testWidgets(
      disposeDuringConfirmation
          ? 'service confirmation after disposal does not dispatch'
          : 'service confirmation uses replacement provider',
      (tester) async {
        tester.view.physicalSize = const Size(420, 500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final first = SettingsRepo();
        final next = SettingsRepo();
        for (final repo in [first, next]) {
          when(repo.loadSnapshot).thenAnswer(
            (_) async => const SettingsSnapshot(services: [service]),
          );
          when(
            () => repo.setServiceEnabled(service, false),
          ).thenAnswer((_) async {});
        }
        final boot = BootRepo();
        when(
          boot.loadSnapshot,
        ).thenAnswer((_) async => const BootLogoSnapshot(status: null));
        final about = AboutRepo();
        when(about.loadSnapshot).thenThrow(Exception('unavailable'));
        final devices = DevicesRepo();
        when(devices.loadSnapshot).thenAnswer(
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
        final display = DisplayRepo();
        when(display.loadSnapshot).thenAnswer(
          (_) async => const DisplaySnapshot(
            overdriveEnabled: null,
            overdriveSupported: false,
            xrandrOutputName: null,
            availableRefreshRates: null,
            currentRefreshRate: null,
          ),
        );
        overrides(SettingsRepo repo) => [
          settingsRepositoryProvider.overrideWithValue(repo),
          bootLogoRepositoryProvider.overrideWithValue(boot),
          aboutRepositoryProvider.overrideWithValue(about),
          devicesRepositoryProvider.overrideWithValue(devices),
          displayRepositoryProvider.overrideWithValue(display),
        ];
        final container = ProviderContainer.test(overrides: overrides(first));
        final visible = ValueNotifier(true);
        addTearDown(visible.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: ValueListenableBuilder<bool>(
                  valueListenable: visible,
                  builder: (_, show, _) =>
                      show ? const SettingsPage() : const SizedBox(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // About is unavailable in this fixture; dismiss its shared error dialog.
        if (find.text('Close').evaluate().isNotEmpty) {
          await tester.tap(find.text('Close').last);
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(find.text('Test service'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Test service'));
        await tester.pumpAndSettle();
        final old = container.read(settingsBlocProvider.bloc);
        if (disposeDuringConfirmation) {
          visible.value = false;
          await tester.pumpAndSettle();
        } else {
          container.updateOverrides(overrides(next));
          await tester.pumpAndSettle();
          expect(old.isClosed, isTrue);
        }
        await tester.tap(find.text('Apply').last);
        await tester.pumpAndSettle();
        verifyNever(() => first.setServiceEnabled(service, false));
        if (disposeDuringConfirmation) {
          verifyNever(() => next.setServiceEnabled(service, false));
        } else {
          verify(() => next.setServiceEnabled(service, false)).called(1);
          String? copied;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          await tester.ensureVisible(find.text('Copy GitHub link'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Copy GitHub link'));
          await tester.pumpAndSettle();
          expect(find.text('Copied GitHub link'), findsOneWidget);
          expect(
            copied,
            'https://github.com/Prn-Ice/LenovoLegionLinuxFrontend',
          );
          expect(find.text('Manifest version: 1.0.0+1'), findsOneWidget);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                throw PlatformException(code: 'clipboard-error');
              }
              return null;
            },
          );
          await tester.ensureVisible(find.text('Copy issue link'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Copy issue link'));
          await tester.pumpAndSettle();
          expect(find.text('Copied GitHub link'), findsNothing);
          expect(find.text('Copy GitHub link'), findsOneWidget);
          expect(find.text('Action could not be completed'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        container.dispose();
        await tester.pump();
      },
    );
  }
}
