import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_cli_service.dart';

void main() {
  test('non-fan commands opt out of hwmon discovery', () async {
    late String executable;
    late List<String> arguments;
    final service = LegionCliService(
      cliPath: '/bin/legion_cli',
      processRunner: (command, args) async {
        executable = command;
        arguments = args;
        return ProcessResult(1, 0, '', '');
      },
    );

    await service.runCommand(const [
      'set-feature',
      'PlatformProfileFeature',
      'custom',
    ]);

    expect(executable, '/bin/legion_cli');
    expect(arguments, const [
      '--donotexpecthwmon',
      'set-feature',
      'PlatformProfileFeature',
      'custom',
    ]);
  });

  test('fan controller commands continue to require hwmon discovery', () async {
    final commands = <List<String>>[];
    final service = LegionCliService(
      cliPath: '/bin/legion_cli',
      processRunner: (command, args) async {
        commands.add(args);
        return ProcessResult(1, 0, '', '');
      },
    );

    await service.runCommand(const [
      'fancurve-write-preset-to-hw',
      'balanced-ac',
    ]);
    await service.runCommand(const ['minifancurve-enable']);
    await service.runCommand(const ['lockfancontroller-disable']);
    await service.runCommand(const ['maximumfanspeed-enable']);

    expect(commands, const [
      ['fancurve-write-preset-to-hw', 'balanced-ac'],
      ['minifancurve-enable'],
      ['lockfancontroller-disable'],
      ['maximumfanspeed-enable'],
    ]);
  });

  test('explicit hwmon opt-out is not duplicated', () async {
    late List<String> arguments;
    final service = LegionCliService(
      cliPath: '/bin/legion_cli',
      processRunner: (command, args) async {
        arguments = args;
        return ProcessResult(1, 0, '', '');
      },
    );

    await service.runCommand(const [
      '--donotexpecthwmon',
      'graphics-mode',
      'status',
    ]);

    expect(arguments, const ['--donotexpecthwmon', 'graphics-mode', 'status']);
  });
}
