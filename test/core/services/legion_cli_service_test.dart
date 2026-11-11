import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_cli_service.dart';

void main() {
  test(
    'shares delayed path resolution and pins all reads to that CLI',
    () async {
      final path = Completer<String>();
      var resolutions = 0;
      final executions = <String>[];
      final service = LegionCliService(
        pathResolver: () {
          resolutions++;
          return path.future;
        },
        processRunner: (command, args) async {
          executions.add(command);
          return ProcessResult(1, 0, "", "");
        },
      );
      final first = service.runCommand(['--help']);
      final second = service.runCommand(['graphics-mode', 'status']);
      expect(executions, isEmpty);
      path.complete('/trusted/legion_cli');
      await Future.wait([first, second]);
      expect(resolutions, 1);
      expect(executions, ['/trusted/legion_cli', '/trusted/legion_cli']);
      expect(await service.resolvePath(), '/trusted/legion_cli');
    },
  );

  test(
    'disposal during path resolution prevents a late read process',
    () async {
      final path = Completer<String>();
      var executions = 0;
      final service = LegionCliService(
        pathResolver: () => path.future,
        processRunner: (command, args) async {
          executions++;
          return ProcessResult(1, 0, "", "");
        },
      );
      final rejected = expectLater(
        service.runCommand(['--help']),
        throwsStateError,
      );
      service.close();
      path.complete('/trusted/legion_cli');
      await rejected;
      expect(executions, 0);
    },
  );
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
