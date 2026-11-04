import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/app_failure.dart';
import 'package:legion_frontend/core/services/legion_cli_service.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/services/legion_frontend_bridge_service.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/core/services/power_profile_service.dart';
import 'package:legion_frontend/core/services/xrandr_service.dart';
import 'package:legion_frontend/features/battery/repository/battery_repository.dart';
import 'package:legion_frontend/features/boot_logo/repository/boot_logo_repository.dart';
import 'package:legion_frontend/features/dashboard/repository/dashboard_repository.dart';
import 'package:legion_frontend/features/devices/repository/devices_repository.dart';
import 'package:legion_frontend/features/dgpu/models/graphics_mode.dart';
import 'package:legion_frontend/features/dgpu/repository/dgpu_repository.dart';
import 'package:legion_frontend/features/display/repository/display_repository.dart';
import 'package:legion_frontend/features/fans/models/fan_curve.dart';
import 'package:legion_frontend/features/fans/repository/fans_repository.dart';
import 'package:legion_frontend/features/lighting/repository/lighting_repository.dart';
import 'package:legion_frontend/features/power/repository/power_repository.dart';
import 'package:mocktail/mocktail.dart';

class _Sysfs extends Mock implements LegionSysfsService {}

class _Cli extends Mock implements LegionCliService {}

class _Profiles extends Mock implements PowerProfileService {}

class _Xrandr extends Mock implements XrandrService {}

class _Transport implements LegionControlTransport {
  final calls = <(String, List<Object>)>[];
  @override
  Future<void> authorize() async {}
  @override
  Future<void> call(String method, List<Object> arguments) async {
    calls.add((method, arguments));
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('feature writes reach typed transport through the real queue', () async {
    final transport = _Transport();
    final client = LegionControlClient(transport: transport);
    addTearDown(client.close);
    final cli = _Cli();
    final bridge = LegionFrontendBridgeService(
      cliService: cli,
      controlClient: client,
    );
    final sysfs = _Sysfs();
    final profiles = _Profiles();
    final battery = BatteryRepository(
      sysfsService: sysfs,
      bridgeService: bridge,
    );
    final devices = DevicesRepository(
      sysfsService: sysfs,
      bridgeService: bridge,
    );
    final display = DisplayRepository(
      sysfsService: sysfs,
      bridgeService: bridge,
      xrandrService: _Xrandr(),
    );
    final lighting = LightingRepository(
      sysfsService: sysfs,
      bridgeService: bridge,
    );
    final fans = FansRepository(sysfsService: sysfs, bridgeService: bridge);
    final dashboard = DashboardRepository(
      sysfsService: sysfs,
      bridgeService: bridge,
      powerProfileService: profiles,
    );
    final power = PowerRepository(
      sysfsService: sysfs,
      bridgeService: bridge,
      powerProfileService: profiles,
    );
    final dgpu = DgpuRepository(bridgeService: bridge);
    final boot = BootLogoRepository(bridgeService: bridge);
    final actions = <(Future<void> Function(), String, List<Object>)>[
      (
        () => battery.setBatteryConservation(true),
        'SetToggle',
        ['battery-conservation', true],
      ),
      (
        () => battery.setRapidCharging(false),
        'SetToggle',
        ['rapid-charging', false],
      ),
      (() => devices.setTouchpad(true), 'SetToggle', ['touchpad', true]),
      (() => devices.setFnLock(false), 'SetToggle', ['fn-lock', false]),
      (() => devices.setWinKey(true), 'SetFeature', ['WinkeyFeature', '1']),
      (
        () => display.setOverdriveMode(false),
        'SetFeature',
        ['OverdriveFeature', '0'],
      ),
      (() => lighting.setYLogoLight(true), 'SetFeature', ['YLogoLight', '1']),
      (
        () => lighting.setIoPortLight(false),
        'SetFeature',
        ['IOPortLight', '0'],
      ),
      (() => fans.applyCurrentContextPreset(), 'ApplyCurrentFanPreset', []),
      (() => fans.applyPreset('quiet-ac'), 'ApplyFanPreset', ['quiet-ac']),
      (() => fans.setMiniFanCurve(true), 'SetToggle', ['mini-fan-curve', true]),
      (
        () => fans.setLockFanController(false),
        'SetToggle',
        ['lock-fan-controller', false],
      ),
      (
        () => fans.setMaximumFanSpeed(true),
        'SetToggle',
        ['maximum-fan-speed', true],
      ),
      (
        () => dashboard.setHybridMode(false),
        'SetToggle',
        ['hybrid-mode', false],
      ),
      (() => dashboard.applyContextFanPreset(), 'ApplyCurrentFanPreset', []),
      (
        () => dashboard.setOverdriveMode(true),
        'SetFeature',
        ['OverdriveFeature', '1'],
      ),
      (
        () => battery.setBatteryConservation(false),
        'SetToggle',
        ['battery-conservation', false],
      ),
      (
        () => battery.setRapidCharging(true),
        'SetToggle',
        ['rapid-charging', true],
      ),
      (() => power.setCpuOverclock(true), 'SetFeature', ['CPUOverclock', '1']),
      (() => power.setGpuOverclock(false), 'SetFeature', ['GPUOverclock', '0']),
      (
        () => dgpu.setGraphicsMode(GraphicsMode.hybridIgpuOnly),
        'SetGraphicsMode',
        ['hybrid-igpu-only'],
      ),
      (() => boot.restoreBootLogo(), 'RestoreBootLogo', []),
    ];
    for (final (action, method, arguments) in actions) {
      transport.calls.clear();
      await action();
      expect(transport.calls, hasLength(1));
      expect(transport.calls.single.$1, method);
      expect(transport.calls.single.$2, arguments);
    }
    when(() => sysfs.readPlatformProfile()).thenAnswer((_) async => 'custom');
    when(() => sysfs.readOnPowerSupplyMode()).thenAnswer((_) async => true);
    await power.setPowerLimit(PowerRepository.allPowerLimits.first, 60);
    expect(transport.calls.last.$1, 'SetFeature');
    expect(transport.calls.last.$2, ['CPULongtermPowerLimit', '60']);

    const curve = FanCurve(name: 'test', points: []);
    await fans.writeFanCurveToHardware(curve);
    expect(transport.calls.last.$1, 'ApplyFanCurve');
    expect(transport.calls.last.$2, [utf8.encode(curve.toYaml())]);

    final directory = await Directory.systemTemp.createTemp('typed-boot-logo-');
    addTearDown(() => directory.delete(recursive: true));
    final image = File('${directory.path}/logo.bmp');
    await image.writeAsBytes([66, 77, 1, 2]);
    await boot.enableBootLogo(image.path);
    expect(transport.calls.last.$1, 'SetBootLogo');
    expect(transport.calls.last.$2, [
      [66, 77, 1, 2],
    ]);

    transport.calls.clear();
    await expectLater(
      fans.applyPreset('unknown-preset'),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.unavailable,
        ),
      ),
    );
    expect(bridge.commandHistory.last.succeeded, isFalse);
    await expectLater(
      devices.setCamera(true),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.unavailable,
        ),
      ),
    );
    await expectLater(
      lighting.setWhiteKeyboardBacklight(true),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.unavailable,
        ),
      ),
    );
    expect(transport.calls, isEmpty);
    verifyZeroInteractions(cli);
  });
}
