// Opt-in rendered evidence, not golden baselines or hardware integration tests.
// flutter test test/visual_handoff_review_test.dart --dart-define=VISUAL_REVIEW=true
// Output: build/visual-review/*.png.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/core/widgets/app_shell_components.dart';
import 'package:yaru/yaru.dart';

import 'package:legion_frontend/features/about/bloc/about_bloc.dart';
import 'package:legion_frontend/features/about/bloc/about_event.dart';
import 'package:legion_frontend/features/about/bloc/about_state.dart';
import 'package:legion_frontend/features/about/providers/about_provider.dart';
import 'package:legion_frontend/features/automation/bloc/automation_bloc.dart';
import 'package:legion_frontend/features/automation/bloc/automation_event.dart';
import 'package:legion_frontend/features/automation/bloc/automation_state.dart';
import 'package:legion_frontend/features/automation/providers/automation_provider.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';
import 'package:legion_frontend/features/lighting/providers/lighting_provider.dart';
import 'support/keyboard_automation_fakes.dart';
import 'package:legion_frontend/features/power/bloc/power_bloc.dart';
import 'package:legion_frontend/features/power/bloc/power_event.dart';
import 'package:legion_frontend/features/power/bloc/power_state.dart';
import 'package:legion_frontend/features/power/models/power_mode.dart';
import 'package:legion_frontend/features/power/models/power_limit.dart';
import 'package:legion_frontend/features/power/providers/power_provider.dart';
import 'package:legion_frontend/features/power/repository/power_repository.dart';
import 'package:legion_frontend/features/sensors/bloc/live_sensor_bloc.dart';
import 'package:legion_frontend/features/sensors/bloc/live_sensor_event.dart';
import 'package:legion_frontend/features/sensors/bloc/live_sensor_state.dart';
import 'package:legion_frontend/features/sensors/providers/live_sensor_provider.dart';
import 'package:legion_frontend/features/battery/bloc/battery_bloc.dart';
import 'package:legion_frontend/features/battery/bloc/battery_event.dart';
import 'package:legion_frontend/features/battery/bloc/battery_state.dart';
import 'package:legion_frontend/features/battery/providers/battery_provider.dart';
import 'package:legion_frontend/features/boot_logo/bloc/boot_logo_bloc.dart';
import 'package:legion_frontend/features/boot_logo/bloc/boot_logo_event.dart';
import 'package:legion_frontend/features/boot_logo/bloc/boot_logo_state.dart';
import 'package:legion_frontend/features/boot_logo/models/boot_logo_status.dart';
import 'package:legion_frontend/features/boot_logo/providers/boot_logo_provider.dart';
import 'package:legion_frontend/features/dashboard/bloc/dashboard_bloc.dart';
import 'package:legion_frontend/features/dashboard/bloc/dashboard_event.dart';
import 'package:legion_frontend/features/dashboard/bloc/dashboard_state.dart';
import 'package:legion_frontend/features/dashboard/providers/dashboard_provider.dart';
import 'package:legion_frontend/features/devices/bloc/devices_bloc.dart';
import 'package:legion_frontend/features/devices/bloc/devices_event.dart';
import 'package:legion_frontend/features/devices/bloc/devices_state.dart';
import 'package:legion_frontend/features/devices/providers/devices_provider.dart';
import 'package:legion_frontend/features/display/bloc/display_bloc.dart';
import 'package:legion_frontend/features/display/bloc/display_event.dart';
import 'package:legion_frontend/features/display/bloc/display_state.dart';
import 'package:legion_frontend/features/display/providers/display_provider.dart';
import 'package:legion_frontend/features/navigation/bloc/navigation_bloc.dart';
import 'package:legion_frontend/features/navigation/bloc/navigation_event.dart';
import 'package:legion_frontend/features/navigation/models/app_section.dart';
import 'package:legion_frontend/features/navigation/providers/navigation_provider.dart';
import 'package:legion_frontend/features/navigation/view/navigation_shell.dart';
import 'package:legion_frontend/features/platform_surfaces/models/platform_event.dart';
import 'package:legion_frontend/features/platform_surfaces/widgets/platform_osd.dart';
import 'package:legion_frontend/features/settings/bloc/settings_bloc.dart';
import 'package:legion_frontend/features/settings/bloc/settings_event.dart';
import 'package:legion_frontend/features/settings/bloc/settings_state.dart';
import 'package:legion_frontend/features/settings/models/service_control.dart';
import 'package:legion_frontend/features/settings/models/appearance_theme.dart';
import 'package:legion_frontend/features/settings/providers/settings_provider.dart';

class _About extends MockBloc<AboutEvent, AboutState> implements AboutBloc {}

class _Power extends MockBloc<PowerEvent, PowerState> implements PowerBloc {}

class _Sensors extends MockBloc<LiveSensorEvent, LiveSensorState>
    implements LiveSensorBloc {}

class _Automation extends MockBloc<AutomationEvent, AutomationState>
    implements AutomationBloc {}

class _Battery extends MockBloc<BatteryEvent, BatteryState>
    implements BatteryBloc {}

class _BootLogo extends MockBloc<BootLogoEvent, BootLogoState>
    implements BootLogoBloc {}

class _Dashboard extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

class _Devices extends MockBloc<DevicesEvent, DevicesState>
    implements DevicesBloc {}

class _Display extends MockBloc<DisplayEvent, DisplayState>
    implements DisplayBloc {}

class _Settings extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

const _enabled = bool.fromEnvironment('VISUAL_REVIEW');
const _output = String.fromEnvironment(
  'VISUAL_REVIEW_DIR',
  defaultValue: 'build/visual-review',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_enabled) return;
    WidgetController.hitTestWarningShouldBeFatal = true;
    // Use Flutter's generated manifest so package-qualified family names and
    // icon fonts match the application, rather than the test runner's Ahem font.
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
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  for (final brightness in Brightness.values) {
    for (final size in [const Size(1280, 900), const Size(420, 500)]) {
      final variant =
          '${brightness.name}-${size.width.toInt()}x${size.height.toInt()}';
      for (final section in [
        AppSection.settings,
        AppSection.automation,
        AppSection.power,
      ]) {
        testWidgets('${section.name} $variant', (tester) async {
          final navigation = NavigationBloc()
            ..add(NavigationSectionSelected(section));
          await tester.pump();
          final about = _About();
          final power = _Power();
          final sensors = _Sensors();
          whenListen(
            power,
            const Stream<PowerState>.empty(),
            initialState: PowerState.initial().copyWith(
              currentMode: const PowerMode('balanced'),
              availableModes: const [
                PowerMode('quiet'),
                PowerMode('balanced'),
                PowerMode('performance'),
                PowerMode('custom'),
              ],
              onPowerSupply: false,
              // Synthetic current value beside the existing model reference.
              powerLimits: [
                PowerLimitReading(
                  spec: PowerRepository.allPowerLimits.first,
                  value: 55,
                  hardwareDefault: 54,
                ),
              ],
            ),
          );
          whenListen(
            sensors,
            const Stream<LiveSensorState>.empty(),
            initialState: LiveSensorState.initial().copyWith(isLoading: false),
          );
          final automation = _Automation();
          final battery = _Battery();
          final boot = _BootLogo();
          final dashboard = _Dashboard();
          final devices = _Devices();
          final display = _Display();
          final settings = _Settings();
          whenListen(
            about,
            const Stream<AboutState>.empty(),
            initialState: AboutState.initial(),
          );
          whenListen(
            automation,
            const Stream<AutomationState>.empty(),
            initialState: AutomationState.initial().copyWith(
              hasLoaded: true,
              config: AutomationConfig(
                profiles: {
                  KeyboardPowerMode.quiet: 'Night',
                  KeyboardPowerMode.performance: 'Gaming',
                },
              ),
            ),
          );
          whenListen(
            battery,
            const Stream<BatteryState>.empty(),
            initialState: BatteryState.initial().copyWith(
              batteryPercent: 78,
              batteryCharging: false,
              rapidChargingSupported: true,
              rapidChargingEnabled: true,
            ),
          );
          whenListen(
            boot,
            const Stream<BootLogoState>.empty(),
            initialState: BootLogoState.initial().copyWith(
              status: const BootLogoStatus(
                isCustomEnabled: false,
                requiredWidth: 1920,
                requiredHeight: 1080,
              ),
            ),
          );
          whenListen(
            dashboard,
            const Stream<DashboardState>.empty(),
            initialState: DashboardState.initial(),
          );
          whenListen(
            devices,
            const Stream<DevicesState>.empty(),
            initialState: DevicesState.initial().copyWith(
              touchpadSupported: true,
              touchpadEnabled: true,
              fnLockSupported: true,
              fnLockEnabled: false,
            ),
          );
          whenListen(
            display,
            const Stream<DisplayState>.empty(),
            initialState: DisplayState.initial().copyWith(
              overdriveSupported: true,
              overdriveEnabled: false,
              xrandrOutputName: 'eDP-1',
              availableRefreshRates: [60.0, 165.0],
              currentRefreshRate: 165.0,
            ),
          );
          whenListen(
            settings,
            const Stream<SettingsState>.empty(),
            initialState: SettingsState.initial().copyWith(
              services: const [
                ServiceControl(
                  service: ControlService.legiondStack,
                  label: 'Legion control service',
                  units: ['legion-control.service'],
                  supported: true,
                  active: true,
                  enabled: true,
                ),
              ],
            ),
          );
          await _render(
            tester,
            size,
            brightness,
            ProviderScope(
              overrides: [
                powerBlocProvider.overrideWith((ref) => power),
                liveSensorBlocProvider.overrideWith((ref) => sensors),
                rgbLightingRepositoryProvider.overrideWithValue(
                  RecordingKeyboard(),
                ),
                spectrumRgbRepositoryProvider.overrideWithValue(
                  NoNativeKeyboard(),
                ),
                rgbLightingStoreProvider.overrideWithValue(
                  MemoryLightingProfiles(),
                ),
                navigationBlocProvider.overrideWith((ref) => navigation),
                aboutBlocProvider.overrideWith((ref) => about),
                automationBlocProvider.overrideWith((ref) => automation),
                batteryBlocProvider.overrideWith((ref) => battery),
                bootLogoBlocProvider.overrideWith((ref) => boot),
                dashboardBlocProvider.overrideWith((ref) => dashboard),
                devicesBlocProvider.overrideWith((ref) => devices),
                displayBlocProvider.overrideWith((ref) => display),
                settingsBlocProvider.overrideWith((ref) => settings),
              ],
              child: const NavigationShell(),
            ),
          );
          await _capture(tester, '${section.name}-$variant-top');
          if (section == AppSection.power) {
            await tester.ensureVisible(find.text('Reference').first);
            await tester.pumpAndSettle();
            await _capture(tester, 'power-reference-$variant');
          }
          // Capture the end of the real page too; a first viewport cannot prove
          // that lower settings and recovery actions remain reachable.
          final scrollables = find.descendant(
            of: find.byType(AppPageBody),
            matching: find.byType(Scrollable),
          );
          if (scrollables.evaluate().isNotEmpty) {
            final pageScroll = scrollables.first;
            await tester.drag(pageScroll, const Offset(0, -2400));
            await tester.pumpAndSettle();
            await _capture(tester, '${section.name}-$variant-bottom');
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          debugDisableShadows = true;
        }, skip: !_enabled);
      }

      testWidgets('OSD $variant', (tester) async {
        await _render(
          tester,
          size,
          brightness,
          Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    PlatformOsd(
                      event: PowerModeChanged(
                        label: 'Performance',
                        powerModeValue: 'performance',
                      ),
                    ),
                    SizedBox(height: 24),
                    PlatformOsd(
                      event: KeyboardBrightnessChanged(fraction: 0.75),
                    ),
                    SizedBox(height: 24),
                    PlatformOsd(event: FanBoostChanged(enabled: null)),
                    SizedBox(height: 24),
                    PlatformOsd(
                      event: AutomationChanged(
                        description: 'Performance keyboard profile applied.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await _capture(tester, 'osd-$variant');
        debugDisableShadows = true;
      }, skip: !_enabled);
    }
  }
}

Future<void> _render(
  WidgetTester tester,
  Size size,
  Brightness brightness,
  Widget child,
) async {
  debugDisableShadows = false;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    YaruTheme(
      data: const YaruThemeData(),
      builder: (context, yaru, _) {
        final themes = appearanceThemes(
          brightness == Brightness.dark ? 'performance' : 'quiet',
          yaru,
        );
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: themes.theme,
          darkTheme: themes.darkTheme,
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          home: RepaintBoundary(
            key: const ValueKey('review-capture'),
            child: child,
          ),
        );
      },
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  // A render exception is a failure, not evidence to silently capture and bless.
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('review-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory = await Directory(_output).create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}
