import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../experiments/dart_helper_commands.dart';

void expectFormatException(void Function() action) {
  expect(action, throwsA(isA<FormatException>()));
}

void main() {
  group('feature boundary validation', () {
    test('accepts the independent profile and boolean allow-lists', () {
      const profiles = [
        'quiet',
        'low-power',
        'power-saver',
        'balanced',
        'performance',
        'balanced-performance',
        'custom',
        'max-power',
      ];
      for (final profile in profiles) {
        final command = buildFeatureFromSerializedInput(
          'PlatformProfileFeature',
          profile,
        );
        expect(command.arguments.last, profile);
      }
      const booleans = [
        'OverdriveFeature',
        'WinkeyFeature',
        'CPUOverclock',
        'GPUOverclock',
        'YLogoLight',
        'IOPortLight',
      ];
      for (final feature in booleans) {
        for (final value in ['0', '1']) {
          expect(
            buildFeatureFromSerializedInput(feature, value).arguments.last,
            value,
          );
        }
      }
    });

    test('rejects unknown profiles, booleans, and mismatched typed values', () {
      expectFormatException(
        () =>
            buildFeatureFromSerializedInput('PlatformProfileFeature', 'turbo'),
      );
      expectFormatException(
        () => buildFeatureFromSerializedInput('OverdriveFeature', '2'),
      );
      expectFormatException(
        () => buildFeatureCommand(
          ControlFeature.overdrive,
          const IntegerValue(1),
        ),
      );
      expectFormatException(
        () => buildFeatureCommand(
          ControlFeature.cpuLongtermPowerLimit,
          const BooleanValue(true),
        ),
      );
    });

    test('accepts each integer feature at both native bounds', () {
      const bounds = <(ControlFeature, String, int, int)>[
        (ControlFeature.cpuLongtermPowerLimit, 'CPULongtermPowerLimit', 5, 200),
        (
          ControlFeature.cpuShorttermPowerLimit,
          'CPUShorttermPowerLimit',
          5,
          200,
        ),
        (ControlFeature.cpuPeakPowerLimit, 'CPUPeakPowerLimit', 1, 200),
        (
          ControlFeature.cpuCrossLoadingPowerLimit,
          'CPUCrossLoadingPowerLimit',
          1,
          100,
        ),
        (ControlFeature.cpuApusPptPowerLimit, 'CPUAPUSPPTPowerLimit', 1, 100),
        (ControlFeature.gpuCtgppPowerLimit, 'GPUCTGPPowerLimit', 1, 200),
        (ControlFeature.gpuPpabPowerLimit, 'GPUPPABPowerLimit', 1, 200),
        (ControlFeature.gpuBoostClock, 'GPUBoostClock', 1, 10000),
        (ControlFeature.gpuTemperatureLimit, 'GPUTemperatureLimit', 1, 120),
      ];
      for (final (feature, wireName, minimum, maximum) in bounds) {
        expect(buildFeatureCommand(feature, IntegerValue(minimum)).arguments, [
          '--donotexpecthwmon',
          'set-feature',
          wireName,
          '$minimum',
        ]);
        expect(buildFeatureCommand(feature, IntegerValue(maximum)).arguments, [
          '--donotexpecthwmon',
          'set-feature',
          wireName,
          '$maximum',
        ]);
      }
    });

    test('rejects each integer feature immediately outside both bounds', () {
      const bounds = <(ControlFeature, int, int)>[
        (ControlFeature.cpuLongtermPowerLimit, 5, 200),
        (ControlFeature.cpuShorttermPowerLimit, 5, 200),
        (ControlFeature.cpuPeakPowerLimit, 1, 200),
        (ControlFeature.cpuCrossLoadingPowerLimit, 1, 100),
        (ControlFeature.cpuApusPptPowerLimit, 1, 100),
        (ControlFeature.gpuCtgppPowerLimit, 1, 200),
        (ControlFeature.gpuPpabPowerLimit, 1, 200),
        (ControlFeature.gpuBoostClock, 1, 10000),
        (ControlFeature.gpuTemperatureLimit, 1, 120),
      ];
      for (final (feature, minimum, maximum) in bounds) {
        expectFormatException(
          () => buildFeatureCommand(feature, IntegerValue(minimum - 1)),
        );
        expectFormatException(
          () => buildFeatureCommand(feature, IntegerValue(maximum + 1)),
        );
      }
    });

    test('rejects malformed decimal forms and overflow', () {
      for (final value in [
        '1\n',
        ' 1',
        '+1',
        '-1',
        '01',
        '1.0',
        '999999999999999999999999',
      ]) {
        expectFormatException(
          () => buildFeatureFromSerializedInput('GPUBoostClock', value),
        );
      }
    });

    test('enforces the 128 UTF-8-byte input boundary', () {
      final accepted = 'é' * 64;
      final rejected = '${'é' * 64}a';
      validateBoundedInput(accepted, 'value');
      expectFormatException(() => validateBoundedInput(rejected, 'value'));
      expectFormatException(
        () => buildFeatureFromSerializedInput(rejected, '1'),
      );
    });
  });

  group('allow-listed command construction', () {
    test('uses every toggle spelling and flag for enable and disable', () {
      const expected = <(ControlCapability, String, bool)>[
        (ControlCapability.hybridMode, 'hybrid-mode', true),
        (ControlCapability.batteryConservation, 'batteryconservation', true),
        (ControlCapability.rapidCharging, 'rapid-charging', true),
        (ControlCapability.alwaysOnUsbCharging, 'always-on-usb-charging', true),
        (ControlCapability.touchpad, 'touchpad', true),
        (ControlCapability.fnLock, 'fnlock', true),
        (ControlCapability.miniFanCurve, 'minifancurve', false),
        (ControlCapability.lockFanController, 'lockfancontroller', false),
        (ControlCapability.maximumFanSpeed, 'maximumfanspeed', false),
      ];
      for (final (capability, spelling, needsFlag) in expected) {
        for (final enabled in [false, true]) {
          final arguments = buildToggleCommand(capability, enabled).arguments;
          expect(arguments, [
            if (needsFlag) '--donotexpecthwmon',
            '$spelling-${enabled ? 'enable' : 'disable'}',
          ]);
        }
      }
    });

    test('builds every preset and service from explicit wire values', () {
      const presets = [
        'quiet-battery',
        'balanced-battery',
        'performance-battery',
        'balanced-performance-battery',
        'quiet-ac',
        'balanced-ac',
        'performance-ac',
        'balanced-performance-ac',
      ];
      for (var index = 0; index < presets.length; index++) {
        expect(parsePreset(presets[index]), FanPreset.values[index]);
      }
      expect(
        parseServiceId('power_profiles_daemon'),
        ServiceId.powerProfilesDaemon,
      );
      expect(parseServiceId('legiond_stack'), ServiceId.legiondStack);
      for (final value in ['missing', 'legiond', 'power-profiles-daemon']) {
        expectFormatException(() => parseServiceId(value));
      }
      expectFormatException(() => parsePreset('quiet'));
    });

    test('builds file argv with spaces without reading the file', () {
      final file = File('/tmp/AppImage with spaces/logo.bmp');
      expect(buildBootLogoCommand(file).arguments, [
        '--donotexpecthwmon',
        'boot-logo',
        'enable',
        file.path,
      ]);
      expect(buildFanCurveFileCommand(file).arguments, [
        'fancurve-write-file-to-hw',
        file.path,
      ]);
    });

    test('keeps conservation order and graphics allow-lists', () {
      expect(buildConservationCommand(0, 100).arguments, [
        '--donotexpecthwmon',
        'custom-conservation-mode-apply',
        '0',
        '100',
      ]);
      expectFormatException(() => buildConservationCommand(51, 50));
      expectFormatException(() => buildConservationCommand(-1, 50));
      for (final (wire, mode) in [
        ('hybrid', GraphicsMode.hybrid),
        ('hybrid-igpu-only', GraphicsMode.hybridIgpuOnly),
        ('discrete', GraphicsMode.discrete),
      ]) {
        expect(parseGraphicsMode(wire), mode);
        expect(buildGraphicsCommand(mode).arguments[3], wire);
      }
      expectFormatException(() => parseGraphicsMode('unknown'));
      expect(parseBootGraphicsMode('hybrid'), BootGraphicsMode.hybrid);
      expectFormatException(() => parseBootGraphicsMode('discrete'));
    });
  });

  group('payload validation', () {
    test('checks actual fan and boot-logo maxima before byte scanning', () {
      final fanMaximum = List<int>.filled(fanCurvePayloadLimit, 0);
      final logoMaximum = List<int>.filled(bootLogoPayloadLimit, 0);
      validatePayload(fanMaximum, fanCurvePayloadLimit);
      validatePayload(logoMaximum, bootLogoPayloadLimit);
      expectFormatException(
        () => validatePayload([...fanMaximum, 256], fanCurvePayloadLimit),
      );
      expectFormatException(
        () => validatePayload([...logoMaximum, 256], bootLogoPayloadLimit),
      );
    });
  });

  group('backend exit classification', () {
    test('keeps every backend category and status contract distinct', () {
      for (final backend in BackendCategory.values) {
        expect(classifyBackendExit(backend, 0), BackendOutcome.success);
        expect(classifyBackendExit(backend, 1), BackendOutcome.commandFailed);
        expect(classifyBackendExit(backend, 99), BackendOutcome.commandFailed);
      }
      expect(
        classifyBackendExit(BackendCategory.cli, 2),
        BackendOutcome.unavailable,
      );
      expect(
        classifyBackendExit(BackendCategory.cli, 3),
        BackendOutcome.notSupported,
      );
      expect(
        classifyBackendExit(BackendCategory.graphics, 2),
        BackendOutcome.graphicsBlocked,
      );
      expect(
        classifyBackendExit(BackendCategory.graphics, 3),
        BackendOutcome.graphicsPending,
      );
      for (final backend in [
        BackendCategory.systemctl,
        BackendCategory.bootHelper,
      ]) {
        expect(classifyBackendExit(backend, 2), BackendOutcome.commandFailed);
        expect(classifyBackendExit(backend, 3), BackendOutcome.commandFailed);
      }
    });
  });
}
