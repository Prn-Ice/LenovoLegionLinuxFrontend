import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/gpu_process_scan.dart';
import 'package:legion_frontend/core/services/drm_process_service.dart';

void main() {
  const integrated = '0000:05:00.0';
  const discrete = '0000:01:00.0';
  late Directory proc;
  late DrmProcessService service;
  late String devicePath;

  setUp(() async {
    proc = await Directory.systemTemp.createTemp('drm-process-');
    devicePath = '${proc.path}/dev';
    service = DrmProcessService(
      procPath: proc.path,
      pciPath: '${proc.path}/pci',
      devicePath: devicePath,
    );
    await Directory('${service.pciPath}/devices/$integrated/drm/renderD128')
        .create(recursive: true);
    addTearDown(() async {
      if (await proc.exists()) await proc.delete(recursive: true);
    });
  });

  Future<void> process(
    int pid, {
    required String name,
    required List<String> fdinfo,
    String? commandLine,
    String? executable,
    List<String> devices = const [],
  }) async {
    final directory = Directory('${proc.path}/$pid');
    await directory.create(recursive: true);
    if (name.isNotEmpty) {
      await File('${directory.path}/comm').writeAsString('$name\n');
    }
    if (commandLine != null) {
      await File('${directory.path}/cmdline').writeAsString(commandLine);
    }
    if (executable != null) {
      await Link('${directory.path}/exe').create(executable);
    }
    for (var index = 0; index < fdinfo.length; index++) {
      final file = File('${directory.path}/fdinfo/$index');
      await file.parent.create(recursive: true);
      await file.writeAsString(fdinfo[index]);
    }
    final handles = devices.isEmpty
        ? List.filled(fdinfo.length, 'dri/renderD128')
        : devices;
    for (final (index, device) in handles.indexed) {
      final link = Link('${directory.path}/fd/$index');
      await link.parent.create(recursive: true);
      await link.create('$devicePath/$device');
    }
  }

  Future<void> addNvidiaDevices() async {
    for (final name in ['card0', 'renderD129', 'card0-HDMI-A-1']) {
      await Directory('${service.pciPath}/devices/$discrete/drm/$name')
          .create(recursive: true);
    }
    await Directory('${service.pciPath}/drivers/nvidia/$discrete')
        .create(recursive: true);
    await Directory(devicePath).create();
    await File('$devicePath/nvidia0').create();
  }

  test('finds NVIDIA clients from links alone', () async {
    await addNvidiaDevices();
    await process(
      2182,
      name: '.kwin_wayland-w',
      executable: '/nix/store/kwin/bin/.kwin_wayland-wrapped',
      fdinfo: const [],
      devices: const ['dri/card0'],
    );
    await process(
      2283,
      name: 'Xwayland',
      fdinfo: const [],
      devices: const ['dri/card0'],
    );
    await process(
      269541,
      name: '.lutris-wrapped',
      fdinfo: const [],
      devices: const ['dri/renderD129', 'nvidia0', 'nvidia0'],
    );
    await process(
      3000,
      name: 'iGPU client',
      fdinfo: const [],
      devices: const ['dri/renderD128'],
    );
    await process(
      3001,
      name: 'control only',
      fdinfo: const [],
      devices: const ['nvidiactl'],
    );

    final scan = await service.readOpenDevices(discrete);

    expect(scan?.processes.map((process) => process.name), [
      'Xwayland',
      'kwin_wayland',
      'lutris',
    ]);
    expect(scan?.processes[1].devices, ['$devicePath/dri/card0']);
    expect(scan?.processes.last.devices, [
      '$devicePath/dri/renderD129',
      '$devicePath/nvidia0',
    ]);
    expect(scan?.processes.last.usedMemoryMib, isNull);
    expect(
      (await service.readProcesses(integrated))?.reporting,
      GpuProcessReporting.notReported,
    );
  });

  test(
    'excludes an ambiguous driver node when more than one NVIDIA GPU is bound',
    () async {
      await addNvidiaDevices();
      await Directory('${service.pciPath}/drivers/nvidia/0000:02:00.0')
          .create();
      await process(
        42,
        name: 'renderer',
        fdinfo: const [],
        devices: const ['dri/renderD129', 'nvidia0'],
      );

      final scan = await service.readOpenDevices(discrete);

      expect(scan?.processes.single.devices, ['$devicePath/dri/renderD129']);
    },
  );

  test(
    'reports unavailable when the GPU device nodes cannot be identified',
    () async {
      expect(await service.readOpenDevices(discrete), isNull);
    },
  );

  test(
    'collects processes for the requested GPU and sums their memory',
    () async {
      await process(
        100,
        name: 'video-editor',
        fdinfo: [
          'pos:\t0\n'
              'drm-driver:\tamdgpu\n'
              'drm-pdev:\t0000:05:00.0\n'
              'drm-client-id:\t7\n'
              'drm-memory-vram:\t2048 KiB\n'
              'drm-memory-gtt:\t4096 KiB\n',
        ],
      );
      await process(
        200,
        name: 'browser',
        fdinfo: [
          'pos:\t0\n'
              'drm-pdev:\t0000:05:00.0\n'
              'drm-client-id:\t8\n',
        ],
      );
      await process(
        300,
        name: 'other-gpu',
        fdinfo: [
          'pos:\t0\n'
              'drm-pdev:\t0000:01:00.0\n'
              'drm-memory-vram:\t8192 KiB\n',
        ],
      );

      final scan = (await service.readProcesses('0000:05:00.0'))!;

      expect(scan.reporting, GpuProcessReporting.reported);
      expect(scan.processes.map((process) => (process.pid, process.name)), [
        (200, 'browser'),
        (100, 'video-editor'),
      ]);
      expect(scan.processes.last.usedMemoryMib, 6);
      expect(scan.processes.first.usedMemoryMib, 0);
    },
  );

  test('combines separate DRM clients owned by one process', () async {
    await process(
      42,
      name: 'compositor',
      fdinfo: [
        'drm-pdev:\t0000:05:00.0\n'
            'drm-memory-vram:\t1024 KiB\n',
        'drm-pdev:\t0000:05:00.0\n'
            'drm-memory-gtt:\t3072 KiB\n',
      ],
    );

    final scan = (await service.readProcesses('0000:05:00.0'))!;

    expect(scan.processes.single.pid, 42);
    expect(scan.processes.single.usedMemoryMib, 4);
  });

  test('reports when DRM clients exist without a GPU address', () async {
    await process(
      42,
      name: 'compositor',
      fdinfo: ['drm-driver:\ti915\ndrm-client-id:\t2\n'],
    );

    final scan = (await service.readProcesses('0000:05:00.0'))!;

    expect(scan.reporting, GpuProcessReporting.notReported);
    expect(scan.processes, isEmpty);
  });

  test('reports no clients when procfs has no DRM file descriptors', () async {
    await process(42, name: 'shell', fdinfo: const []);
    await Directory('${proc.path}/not-a-pid').create();

    final scan = (await service.readProcesses('0000:05:00.0'))!;

    expect(scan.reporting, GpuProcessReporting.noClients);
    expect(scan.processes, isEmpty);
  });

  test('reports DRM clients without statistics as not reported', () async {
    await process(42, name: 'compositor', fdinfo: ['pos:\t0\n']);

    final scan = (await service.readProcesses('0000:05:00.0'))!;

    expect(scan.reporting, GpuProcessReporting.notReported);
    expect(scan.processes, isEmpty);
  });

  test('falls back to the command line for a missing process name', () async {
    await process(
      42,
      name: '',
      commandLine: '/usr/bin/renderer\u0000--flag\u0000',
      fdinfo: ['drm-pdev:\t0000:05:00.0\n'],
    );

    final scan = (await service.readProcesses('0000:05:00.0'))!;

    expect(scan.processes.single.name, 'renderer');
  });

  test('reuses a recent scan until the minimum interval passes', () async {
    var now = DateTime(2026, 1, 1);
    final service = DrmProcessService(
      procPath: proc.path,
      pciPath: '${proc.path}/pci',
      devicePath: devicePath,
      minimumInterval: const Duration(seconds: 10),
      clock: () => now,
    );
    await process(42, name: 'first', fdinfo: ['drm-pdev:\t0000:05:00.0\n']);

    final first = await service.readProcesses('0000:05:00.0');
    expect(first?.processes.single.name, 'first');

    await process(43, name: 'second', fdinfo: ['drm-pdev:\t0000:05:00.0\n']);
    now = now.add(const Duration(seconds: 5));
    final cached = await service.readProcesses('0000:05:00.0');
    expect(cached?.processes.map((process) => process.name), ['first']);

    now = now.add(const Duration(seconds: 6));
    final refreshed = await service.readProcesses('0000:05:00.0');
    expect(refreshed?.processes.map((process) => process.name), [
      'first',
      'second',
    ]);
  });

  test('returns unavailable when procfs cannot be read', () async {
    await proc.delete(recursive: true);

    expect(await service.readProcesses('0000:05:00.0'), isNull);
  });
}
