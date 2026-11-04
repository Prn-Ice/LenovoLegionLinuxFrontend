import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/sysfs_probe.dart';
import 'package:legion_frontend/core/services/legion_cli_service.dart';
import 'package:legion_frontend/core/services/legion_frontend_bridge_service.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/features/about/repository/about_repository.dart';

void main() {
  late Directory root;
  late List<List<String>> commands;
  late AboutRepository repository;
  var cliHealthy = true;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('about-diagnostics-');
    commands = [];
    cliHealthy = true;
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/sysfs/alternate-layout.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    fixture['sys/class/dmi/id/product_serial'] = 'PRIVATE-SERIAL';
    fixture['sys/class/dmi/id/product_uuid'] = 'PRIVATE-UUID';
    fixture['sys/class/hwmon/hwmon7/fan2_input'] = 'invalid';
    for (final entry in fixture.entries) {
      final file = File('${root.path}/${entry.key}');
      await file.parent.create(recursive: true);
      await file.writeAsString('${entry.value}\n');
    }
    final cli = LegionCliService(
      cliPath: '${root.path}/PRIVATE-USER/legion_cli',
      processRunner: (executable, arguments) async {
        commands.add(arguments);
        return ProcessResult(
          0,
          cliHealthy ? 0 : 1,
          arguments.contains('--version') ? 'fixture-cli-1.0' : 'help',
          cliHealthy ? '' : 'Error in ${root.path}/PRIVATE-USER',
        );
      },
    );
    repository = AboutRepository(
      sysfs: LegionSysfsService(
        sysRoot: '${root.path}/sys',
        procRoot: '${root.path}/proc',
      ),
      cli: cli,
      bridge: LegionFrontendBridgeService(cliService: cli),
      processRunner: (executable, arguments) async {
        expect(executable, anyOf('which', 'systemctl'));
        return ProcessResult(0, 1, '', '');
      },
    );
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'existing snapshot export includes identity, selections and separate write evidence',
    () async {
      final snapshot = await repository.loadSnapshot();
      final report =
          jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>;
      final diagnostics = {
        for (final item in report['diagnostics'] as List)
          (item as Map<String, dynamic>)['id']: item,
      };
      expect(
        report['hardware_model'],
        'Synthetic Legion family (SYNTHETIC-MODEL)',
      );
      expect(report['bios_version'], 'FIXTURE-BIOS');
      expect(report['kernel_version'], isNull);
      expect(report['module_version'], isNull);
      expect(report['cli_version'], 'fixture-cli-1.0');
      expect(report['control_service_active'], isFalse);
      expect(
        diagnostics['battery_conservation']!['frontend_write_available'],
        isTrue,
      );
      expect(diagnostics['fan1_rpm']!['frontend_write_available'], isFalse);
      expect(
        diagnostics['battery_conservation']!['hardware_write_verification'],
        'unverified',
      );
      expect(
        diagnostics['fan1_rpm']!['read']['selected_path'],
        '/sys/class/hwmon/hwmon7/fan1_input',
      );
      expect(diagnostics['fan1_provider']!['value'], 'yogafan');
      expect(diagnostics['fan2_rpm']!['read']['outcome'], 'malformed');
      expect(diagnostics['fan2_rpm']!['read']['selected_path'], isNull);
      expect(diagnostics['bios_version']!['read']['outcome'], 'readable');
      expect(
        snapshot.diagnostics
            .singleWhere((item) => item.id == 'fn_lock')
            .readProbe
            ?.outcome,
        SysfsReadOutcome.missing,
      );
      expect(jsonEncode(report), isNot(contains('PRIVATE-')));
      expect(jsonEncode(report), isNot(contains(root.path)));
      expect(commands, [
        ['--donotexpecthwmon', '--help'],
        ['--donotexpecthwmon', '--version'],
      ]);
      expect(report['command_history'], hasLength(2));
      expect(
        snapshot.commandHistory.every((record) => !record.isPrivileged),
        isTrue,
      );
    },
  );

  test(
    'CLI failure text stays local; hardware discovery still exports',
    () async {
      cliHealthy = false;
      final snapshot = await repository.loadSnapshot();
      expect(snapshot.cliHealthy, isFalse);
      expect(snapshot.cliHealthSummary, contains(root.path));
      expect(snapshot.cliVersion, isNull);
      expect(snapshot.biosVersion, 'FIXTURE-BIOS');
      expect(jsonEncode(snapshot.toJson()), isNot(contains('PRIVATE-')));
      expect(jsonEncode(snapshot.toJson()), isNot(contains(root.path)));
      expect(snapshot.toJson()['hardware_write_verification'], 'unverified');
    },
  );
}
