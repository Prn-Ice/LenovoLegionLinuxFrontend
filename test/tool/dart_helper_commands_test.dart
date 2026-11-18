import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../experiments/dart_helper_commands.dart';

void main() {
  group('feature validation and commands', () {
    test('accepts profiles, booleans, and inclusive integer bounds', () {
      expect(
        buildFeatureFromSerializedInput(
          'PlatformProfileFeature',
          'balanced-performance',
        ).arguments,
        [
          '--donotexpecthwmon',
          'set-feature',
          'PlatformProfileFeature',
          'balanced-performance',
        ],
      );
      expect(
        buildFeatureFromSerializedInput('OverdriveFeature', '1').arguments,
        ['--donotexpecthwmon', 'set-feature', 'OverdriveFeature', '1'],
      );
      expect(
        buildFeatureFromSerializedInput('GPUBoostClock', '10000').arguments,
        ['--donotexpecthwmon', 'set-feature', 'GPUBoostClock', '10000'],
      );
    });

    test('rejects malformed, mismatched, and out-of-range values', () {
      expect(
        () => buildFeatureFromSerializedInput('GPUBoostClock', '01'),
        throwsFormatException,
      );
      expect(
        buildFeatureFromSerializedInput('GPUBoostClock', '10001').isSuccess,
        isFalse,
      );
      expect(
        () => buildFeatureFromSerializedInput('OverdriveFeature', '2'),
        throwsFormatException,
      );
      expect(
        () => buildFeatureFromSerializedInput('missing', '1'),
        throwsFormatException,
      );
      expect(
        () => buildFeatureFromSerializedInput('OverdriveFeature', 'x' * 129),
        throwsFormatException,
      );
    });
  });

  group('command construction', () {
    test('keeps toggle flag and argument order contracts', () {
      expect(
        buildToggleCommand(ControlCapability.miniFanCurve, true).arguments,
        ['minifancurve-enable'],
      );
      expect(buildToggleCommand(ControlCapability.touchpad, false).arguments, [
        '--donotexpecthwmon',
        'touchpad-disable',
      ]);
      expect(buildServiceCommand(ServiceId.legiondStack, true).arguments, [
        'enable',
        '--now',
        'legiond.service',
        'legiond-onresume.service',
        'legiond-cpuset.service',
        'legiond-cpuset.timer',
      ]);
    });

    test('builds a boot-logo command from a File without executing it', () {
      final command = buildBootLogoCommand(File('/tmp/boot-logo.bmp'));

      expect(command.arguments, [
        '--donotexpecthwmon',
        'boot-logo',
        'enable',
        '/tmp/boot-logo.bmp',
      ]);
    });

    test('preserves conservation and graphics boundaries', () {
      expect(buildConservationCommand(0, 100).isSuccess, isTrue);
      expect(
        buildConservationCommand(80, 20).error,
        'invalid conservation limits',
      );
      expect(buildGraphicsCommand(GraphicsMode.hybridIgpuOnly).arguments, [
        '--donotexpecthwmon',
        'graphics-mode',
        'set',
        'hybrid-igpu-only',
        '--json',
      ]);
      expect(buildBootGraphicsCommand(BootGraphicsMode.hybrid).arguments, [
        'request',
        'hybrid',
      ]);
    });

    test(
      'validates serialized capabilities and payload limits at the boundary',
      () {
        expect(
          parseCapability('mini-fan-curve'),
          ControlCapability.miniFanCurve,
        );
        expect(() => parseCapability('unknown'), throwsFormatException);
        expect(parsePreset('quiet-ac'), FanPreset.quietAc);
        expect(() => parseServiceId('unknown'), throwsFormatException);
        expect(
          parseGraphicsMode('hybrid-igpu-only'),
          GraphicsMode.hybridIgpuOnly,
        );
        expect(() => parseBootGraphicsMode('discrete'), throwsFormatException);
        expect(
          validatePayload([0, 255], bootLogoPayloadLimit).isSuccess,
          isTrue,
        );
        expect(
          validatePayload([], fanCurvePayloadLimit).error,
          'payload must not be empty',
        );
        expect(
          validatePayload([256], fanCurvePayloadLimit).error,
          'payload contains a non-byte value',
        );
      },
    );
  });

  group('backend exit classification', () {
    test('keeps generic CLI and graphics meanings separate', () {
      expect(classifyCliExit(0), BackendOutcome.success);
      expect(classifyCliExit(2), BackendOutcome.unavailable);
      expect(classifyCliExit(3), BackendOutcome.notSupported);
      expect(classifyCliExit(1), BackendOutcome.commandFailed);
      expect(
        classifyBackendExit(BackendCategory.graphics, 2),
        BackendOutcome.graphicsBlocked,
      );
      expect(
        classifyBackendExit(BackendCategory.graphics, 3),
        BackendOutcome.graphicsPending,
      );
    });

    test('does not apply CLI or graphics meanings to other backends', () {
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
