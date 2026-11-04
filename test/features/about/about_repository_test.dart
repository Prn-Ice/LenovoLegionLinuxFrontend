import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/sysfs_probe.dart';
import 'package:legion_frontend/core/services/legion_cli_service.dart';
import 'package:legion_frontend/core/services/legion_frontend_bridge_service.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/features/about/repository/about_repository.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_hid_service.dart';

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
      spectrumHid: SpectrumHidService(
        sysfsHidrawRoot: '${root.path}/sys/class/hidraw',
        devRoot: '${root.path}/dev',
      ),
      processRunner: (executable, arguments) async {
        expect(executable, anyOf('which', 'systemctl'));
        return ProcessResult(0, 1, '', '');
      },
    );
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'power report keeps readable files separate from allowed write actions',
    () async {
      const legion = 'sys/module/legion_laptop/drivers/platform:legion';
      // Synthetic values cover every attribute displayed by the Power page.
      final files = {
        '$legion/PNP0C09:00/cpu_longterm_powerlimit': '75',
        '$legion/PNP0C09:00/cpu_shortterm_powerlimit': '90',
        '$legion/PNP0C09:00/cpu_peak_powerlimit': '100',
        '$legion/PNP0C09:00/cpu_cross_loading_powerlimit': '45',
        '$legion/PNP0C09:00/cpu_temperature_limit': '95',
        '$legion/PNP0C09:00/cpu_apu_sppt_powerlimit': '55',
        '$legion/PNP0C09:00/cpu_default_powerlimit': '65',
        '$legion/PNP0C09:00/gpu_ctgp_powerlimit': 'invalid',
        '$legion/PNP0C09:00/gpu_power_target_offset': '15',
        '$legion/PNP0C09:00/gpu_ppab_powerlimit': '20',
        '$legion/PNP0C09:00/gpu_boost_clock': '1500',
        '$legion/PNP0C09:00/gpu_temperature_limit': '87',
        '$legion/PNP0C09:00/cpu_oc': '0',
        '$legion/PNP0C09:00/gpu_oc': '1',
        'sys/bus/platform/drivers/ideapad_acpi/VPC2004:01/camera_power': '1',
      };
      for (final entry in files.entries) {
        final file = File('${root.path}/${entry.key}');
        await file.parent.create(recursive: true);
        await file.writeAsString('${entry.value}\n');
      }
      final report = (await repository.loadSnapshot()).toJson();
      final hid = report['spectrum_hid'] as Map<String, Object?>;
      expect(hid['outcome'], 'rootMissing');
      expect(hid['selected_hidraw_path'], isNull);
      final checks = {
        for (final item in report['diagnostics'] as List)
          (item as Map<String, Object?>)['id']: item,
      };
      for (final id in [
        'camera_power',
        'keyboard_backlight',
        'cpu_default',
        'cpu_temperature',
        'gpu_power_target_offset',
      ]) {
        expect(checks[id]!['frontend_write_available'], isFalse, reason: id);
        expect((checks[id]!['read'] as Map)['outcome'], 'readable', reason: id);
      }
      for (final id in [
        'cpu_longterm',
        'cpu_shortterm',
        'cpu_peak',
        'cpu_cross_loading',
        'cpu_apu_sppt',
        'gpu_ctgp',
        'gpu_ppab',
        'gpu_boost_clock',
        'gpu_temperature',
        'cpu_oc',
        'gpu_oc',
      ]) {
        expect(checks[id]!['frontend_write_available'], isTrue, reason: id);
        expect(
          checks[id]!['hardware_write_verification'],
          'unverified',
          reason: id,
        );
        expect(
          (checks[id]!['read'] as Map)['outcome'],
          id == 'gpu_ctgp' ? 'malformed' : 'readable',
          reason: id,
        );
      }
      expect(
        (checks['cpu_longterm']!['read'] as Map)['selected_path'],
        '/$legion/PNP0C09:00/cpu_longterm_powerlimit',
      );
      expect(checks['cpu_longterm']!['value'], '75');
      expect(checks['cpu_default']!['value'], '65');
      expect((checks['gpu_ctgp']!['read'] as Map)['selected_path'], isNull);
      expect((checks['gpu_ctgp']!['read'] as Map)['attempts'], [
        {'path': '/$legion/legion/gpu_ctgp_powerlimit', 'outcome': 'missing'},
        {
          'path': '/$legion/PNP0C09:00/gpu_ctgp_powerlimit',
          'outcome': 'malformed',
        },
      ]);
      expect(commands, [
        ['--donotexpecthwmon', '--help'],
        ['--donotexpecthwmon', '--version'],
      ]);
    },
  );

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
