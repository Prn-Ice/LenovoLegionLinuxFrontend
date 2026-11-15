import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mocktail/mocktail.dart';
import 'package:legion_frontend/core/providers/system_services_provider.dart';
import 'package:legion_frontend/features/about/models/about_snapshot.dart';
import 'package:legion_frontend/features/about/providers/about_provider.dart';
import 'package:legion_frontend/features/about/repository/about_repository.dart';
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

class _About extends Mock implements AboutRepository {}

class _Boot extends Mock implements BootLogoRepository {}

class _Devices extends Mock implements DevicesRepository {}

class _Display extends Mock implements DisplayRepository {}

/// Synthetic Settings reads keep the native journey off the host's hardware.
List<Override> safeSettingsOverrides() {
  final about = _About();
  when(about.loadSnapshot).thenAnswer(
    (_) async => AboutSnapshot(
      updatedAt: DateTime.now(),
      cliPath: '/integration-test/legion_cli',
      cliPathExists: true,
      pythonAvailable: true,
      controlServiceActive: false,
      systemctlAvailable: true,
      cliHealthy: true,
      cliHealthSummary: 'Synthetic CLI',
      diagnostics: const [],
      kernelVersion: 'Test kernel',
      hardwareModel: 'Journey fixture',
      moduleVersion: 'Test module',
      cliVersion: null,
      commandHistory: const [],
    ),
  );
  final boot = _Boot();
  when(boot.loadSnapshot).thenAnswer(
    (_) async => const BootLogoSnapshot(
      status: BootLogoStatus(
        isCustomEnabled: false,
        requiredWidth: 0,
        requiredHeight: 0,
      ),
    ),
  );
  final devices = _Devices();
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
  final display = _Display();
  when(display.loadSnapshot).thenAnswer(
    (_) async => const DisplaySnapshot(
      overdriveEnabled: null,
      overdriveSupported: false,
      xrandrOutputName: null,
      availableRefreshRates: [],
      currentRefreshRate: null,
    ),
  );
  return [
    aboutRepositoryProvider.overrideWithValue(about),
    bootLogoRepositoryProvider.overrideWithValue(boot),
    devicesRepositoryProvider.overrideWithValue(devices),
    displayRepositoryProvider.overrideWithValue(display),
    portableControlAvailableProvider.overrideWithValue(true),
  ];
}
