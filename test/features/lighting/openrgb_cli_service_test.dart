import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/app_failure.dart';
import 'package:legion_frontend/features/lighting/services/openrgb_cli_service.dart';

void main() {
  final operations =
      <(String, List<String>, Future<void> Function(OpenRgbCliService))>[
        (
          'apply lighting',
          ['-d', '2', '-m', 'Static', '-c', 'FF0000'],
          (service) =>
              service.apply(device: 2, mode: 'Static', colorsHex: ['FF0000']),
        ),
        (
          'load a profile',
          ['-p', 'Desk look'],
          (s) => s.loadProfile('Desk look'),
        ),
        (
          'save a profile',
          ['-sp', 'Desk look'],
          (s) => s.saveProfile('Desk look'),
        ),
      ];
  for (final (description, arguments, write) in operations) {
    test('$description checks the exit status and supports retry', () async {
      var exitCode = 7;
      final calls = <(String, List<String>)>[];
      final service = OpenRgbCliService(
        executable: '/test/openrgb',
        processRunner: (executable, args) async {
          calls.add((executable, List.of(args)));
          return ProcessResult(
            1,
            exitCode,
            'partial output',
            'device rejected',
          );
        },
      );
      await expectLater(
        write(service),
        throwsA(
          isA<AppFailure>()
              .having((e) => e.kind, 'kind', AppFailureKind.commandFailed)
              .having(
                (e) => e.details,
                'details',
                allOf(
                  contains('/test/openrgb'),
                  contains('Exit code: 7'),
                  contains('partial output'),
                  contains('device rejected'),
                ),
              ),
        ),
      );
      expect(calls, hasLength(1));
      expect(calls.single.$1, '/test/openrgb');
      expect(calls.single.$2, arguments);
      exitCode = 0;
      await write(service);
      expect(calls.map((call) => call.$1), ['/test/openrgb', '/test/openrgb']);
      expect(calls.map((call) => call.$2), [arguments, arguments]);
    });

    test('$description reports a launch failure as unavailable', () async {
      final service = OpenRgbCliService(
        processRunner: (executable, args) => throw ProcessException(
          executable,
          args,
          'test executable missing',
          2,
        ),
      );
      await expectLater(
        write(service),
        throwsA(
          isA<AppFailure>()
              .having((e) => e.kind, 'kind', AppFailureKind.unavailable)
              .having(
                (e) => e.details,
                'details',
                contains('test executable missing'),
              ),
        ),
      );
    });
  }

  test(
    'failed discovery leaves the native backend available as a fallback',
    () async {
      final service = OpenRgbCliService(
        processRunner: (_, args) async {
          expect(args, ['--list-devices']);
          return ProcessResult(1, 1, '', 'no server');
        },
      );
      expect(await service.isAvailable(), isFalse);
      expect(await service.listDevices(), isEmpty);
    },
  );

  group('openRgbApplyArgs', () {
    test('mode only', () {
      expect(openRgbApplyArgs(device: 0, mode: 'Static'), [
        '-d',
        '0',
        '-m',
        'Static',
      ]);
    });

    test('mode + single color', () {
      expect(
        openRgbApplyArgs(device: 0, mode: 'Static', colorsHex: ['FF0000']),
        ['-d', '0', '-m', 'Static', '-c', 'FF0000'],
      );
    });

    test('per-key colors join with commas (Direct mode)', () {
      expect(
        openRgbApplyArgs(
          device: 0,
          mode: 'Direct',
          colorsHex: ['FF0000', '00FF00'],
        ),
        ['-d', '0', '-m', 'Direct', '-c', 'FF0000,00FF00'],
      );
    });

    test('zone, brightness and speed, in CLI-required order', () {
      expect(
        openRgbApplyArgs(
          device: 0,
          zone: 1,
          mode: 'Rainbow Wave',
          brightness: 80,
          speed: 50,
        ),
        ['-d', '0', '-z', '1', '-m', 'Rainbow Wave', '-b', '80', '-s', '50'],
      );
    });

    test('color without a mode sets LEDs directly', () {
      expect(openRgbApplyArgs(device: 0, colorsHex: ['FF00FF']), [
        '-d',
        '0',
        '-c',
        'FF00FF',
      ]);
    });
  });

  test(
    'missing OpenRGB is treated as no devices for native fallback',
    () async {
      final devices = await const OpenRgbCliService(
        executable: 'openrgb-executable-that-does-not-exist',
      ).listDevices();
      expect(devices, isEmpty);
    },
  );
}
