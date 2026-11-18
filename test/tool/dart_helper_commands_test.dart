import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../experiments/dart_helper_commands.dart';

void expectFormatException(void Function() action, [String? message]) {
  final matcher = message == null
      ? isA<FormatException>()
      : isA<FormatException>().having(
          (error) => error.message,
          'message',
          message,
        );
  expect(action, throwsA(matcher));
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
        expect(command.arguments, [
          '--donotexpecthwmon',
          'set-feature',
          'PlatformProfileFeature',
          profile,
        ]);
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
          expect(buildFeatureFromSerializedInput(feature, value).arguments, [
            '--donotexpecthwmon',
            'set-feature',
            feature,
            value,
          ]);
        }
      }
    });

    test('rejects unknown profiles, booleans, and mismatched typed values', () {
      expectFormatException(
        () => buildFeatureFromSerializedInput('missing', '1'),
        'unsupported feature or value',
      );
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
        for (final value in [minimum, maximum]) {
          expect(
            buildFeatureFromSerializedInput(wireName, '$value').arguments,
            ['--donotexpecthwmon', 'set-feature', wireName, '$value'],
          );
        }
        for (final value in [minimum - 1, maximum + 1]) {
          expectFormatException(
            () => buildFeatureFromSerializedInput(wireName, '$value'),
          );
        }
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
        '',
        '1\n',
        ' 1',
        '1 ',
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
      expectFormatException(
        () => validateBoundedInput(rejected, 'value'),
        'value exceeds maximum length',
      );
      expectFormatException(
        () => buildFeatureFromSerializedInput(rejected, '1'),
        'feature exceeds maximum length',
      );
      expectFormatException(
        () => buildFeatureFromSerializedInput('OverdriveFeature', rejected),
        'value exceeds maximum length',
      );
      expectFormatException(
        () => parseCapability(accepted),
        'unsupported capability',
      );
      expectFormatException(
        () => parseCapability(rejected),
        'toggle exceeds maximum length',
      );
    });
  });

  group('allow-listed command construction', () {
    test('uses every toggle spelling and flag for enable and disable', () {
      const expected = <(String, String, bool)>[
        ('hybrid-mode', 'hybrid-mode', true),
        ('battery-conservation', 'batteryconservation', true),
        ('rapid-charging', 'rapid-charging', true),
        ('always-on-usb-charging', 'always-on-usb-charging', true),
        ('touchpad', 'touchpad', true),
        ('fn-lock', 'fnlock', true),
        ('mini-fan-curve', 'minifancurve', false),
        ('lock-fan-controller', 'lockfancontroller', false),
        ('maximum-fan-speed', 'maximumfanspeed', false),
      ];
      for (final (wireName, spelling, needsFlag) in expected) {
        final capability = parseCapability(wireName);
        for (final enabled in [false, true]) {
          final arguments = buildToggleCommand(capability, enabled).arguments;
          expect(arguments, [
            if (needsFlag) '--donotexpecthwmon',
            '$spelling-${enabled ? 'enable' : 'disable'}',
          ]);
        }
      }
      expectFormatException(() => parseCapability('unknown'));
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
      for (final preset in presets) {
        expect(buildPresetCommand(parsePreset(preset)).arguments, [
          'fancurve-write-preset-to-hw',
          preset,
        ]);
      }
      const services = {
        'power_profiles_daemon': ['power-profiles-daemon.service'],
        'legiond_stack': [
          'legiond.service',
          'legiond-onresume.service',
          'legiond-cpuset.service',
          'legiond-cpuset.timer',
        ],
      };
      for (final service in services.entries) {
        for (final enabled in [false, true]) {
          expect(
            buildServiceCommand(parseServiceId(service.key), enabled).arguments,
            [enabled ? 'enable' : 'disable', '--now', ...service.value],
          );
        }
      }
      for (final value in ['missing', 'legiond', 'power-profiles-daemon']) {
        expectFormatException(() => parseServiceId(value));
      }
      expectFormatException(() => parsePreset('quiet'));
      expect(buildCurrentPresetCommand().arguments, [
        'fancurve-write-current-preset-to-hw',
      ]);
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
      expect(buildRestoreBootLogoCommand().arguments, [
        '--donotexpecthwmon',
        'boot-logo',
        'restore',
      ]);
      expectFormatException(() => buildBootLogoCommand(File('')));
      expectFormatException(() => buildFanCurveFileCommand(File('')));
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
      expectFormatException(() => buildConservationCommand(0, 101));
      expectFormatException(() => buildConservationCommand(101, 101));
      expectFormatException(() => buildConservationCommand(0, -1));
      for (final limit in [0, 100]) {
        expect(buildConservationCommand(limit, limit).arguments, [
          '--donotexpecthwmon',
          'custom-conservation-mode-apply',
          '$limit',
          '$limit',
        ]);
      }
      for (final (wire, mode) in [
        ('hybrid', GraphicsMode.hybrid),
        ('hybrid-igpu-only', GraphicsMode.hybridIgpuOnly),
        ('discrete', GraphicsMode.discrete),
      ]) {
        expect(parseGraphicsMode(wire), mode);
        expect(buildGraphicsCommand(mode).arguments, [
          '--donotexpecthwmon',
          'graphics-mode',
          'set',
          wire,
          '--json',
        ]);
      }
      expectFormatException(() => parseGraphicsMode('unknown'));
      for (final wire in ['hybrid', 'hybrid-igpu-only']) {
        expect(
          buildBootGraphicsCommand(parseBootGraphicsMode(wire)).arguments,
          ['request', wire],
        );
      }
      expectFormatException(() => parseBootGraphicsMode('discrete'));
    });
  });

  group('payload validation', () {
    test('accepts each payload maximum and rejects one extra valid byte', () {
      for (final (limit, expectedBytes) in [
        (fanCurvePayloadLimit, 65536),
        (bootLogoPayloadLimit, 16777216),
      ]) {
        validatePayload(Uint8List(expectedBytes), limit);
        expectFormatException(
          () => validatePayload(Uint8List(expectedBytes + 1), limit),
          'payload exceeds maximum size',
        );
      }
    });

    test('rejects empty and invalid bytes, with size errors first', () {
      validatePayload([0, 255], fanCurvePayloadLimit);
      expectFormatException(
        () => validatePayload([], fanCurvePayloadLimit),
        'payload must not be empty',
      );
      for (final byte in [-1, 256]) {
        expectFormatException(
          () => validatePayload([byte], fanCurvePayloadLimit),
          'payload contains a non-byte value',
        );
      }
      expectFormatException(
        () => validatePayload([0, 256], 1),
        'payload exceeds maximum size',
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
