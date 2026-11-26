import 'dart:convert';
import 'dart:io';

import '../models/gpu_process.dart';
import '../models/gpu_process_scan.dart';

/// Reads the GPU device handles and DRM client statistics visible in procfs.
class DrmProcessService {
  DrmProcessService({
    this.procPath = '/proc',
    this.pciPath = '/sys/bus/pci',
    this.devicePath = '/dev',
    this.minimumInterval = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String procPath;
  final String pciPath;
  final String devicePath;

  /// Reuse recent process scans between sensor polls.
  final Duration minimumInterval;
  final DateTime Function() _clock;

  static final _drmNode = RegExp(r'^(card|renderD)[0-9]+$');
  static final _driverNode = RegExp(r'^nvidia[0-9]+$');
  static final _pciAddress = RegExp(
    r'^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$',
  );

  final _cache = <(String, bool), ({DateTime at, GpuProcessScan? scan})>{};

  /// Finds processes whose DRM client statistics identify the requested GPU.
  Future<GpuProcessScan?> readProcesses(String pciAddress) =>
      _read(pciAddress, includeMemory: true);

  /// Finds open devices by reading links without opening GPU devices or fdinfo.
  Future<GpuProcessScan?> readOpenDevices(String pciAddress) =>
      _read(pciAddress, includeMemory: false);

  Future<GpuProcessScan?> _read(
    String pciAddress, {
    required bool includeMemory,
  }) async {
    final now = _clock();
    final key = (pciAddress, includeMemory);
    final cached = _cache[key];
    if (cached != null && now.difference(cached.at) < minimumInterval) {
      return cached.scan;
    }

    final scan = await _scan(pciAddress, includeMemory: includeMemory);
    _cache[key] = (at: now, scan: scan);
    return scan;
  }

  Future<GpuProcessScan?> _scan(
    String pciAddress, {
    required bool includeMemory,
  }) async {
    final processes = <GpuProcess>[];
    var readDrmClient = false;
    var readPciAddress = false;

    try {
      final nodes = await _deviceNodes(
        pciAddress,
        includeDriver: !includeMemory,
      );
      if (nodes.isEmpty) return null;

      await for (final process in Directory(
        procPath,
      ).list(followLinks: false)) {
        final pid = int.tryParse(_basename(process.path));
        if (pid == null) continue;

        final openDevices = <String>{};
        int? memoryKib;
        try {
          final descriptors = Directory('${process.path}/fd');
          await for (final fd in descriptors.list(followLinks: false)) {
            if (fd is! Link) continue;
            try {
              // Reading the link leaves its target unopened.
              final target = await fd.target();
              if (!nodes.contains(target)) continue;
              if (!includeMemory) {
                openDevices.add(target);
                continue;
              }

              readDrmClient = true;
              final contents = await File(
                '${process.path}/fdinfo/${_basename(fd.path)}',
              ).readAsString();
              final lines = contents.split('\n');
              final address = lines
                  .where((line) => line.startsWith('drm-pdev:'))
                  .firstOrNull;
              if (address == null) continue;
              readPciAddress = true;
              if (_valueOf(address) != pciAddress) continue;

              memoryKib = lines
                  .where((line) => line.startsWith('drm-memory-'))
                  .fold<int>(
                    memoryKib ?? 0,
                    (sum, line) => sum + _memoryKib(line),
                  );
            } on FileSystemException {
              // A process can close a descriptor before the scan reads it.
            }
          }
        } on FileSystemException {
          // A process can exit or limit access to its file descriptors.
        }

        if (openDevices.isEmpty && memoryKib == null) continue;
        processes.add(
          GpuProcess(
            pid: pid,
            name: await _readName(pid),
            usedMemoryMib: memoryKib == null ? null : memoryKib ~/ 1024,
            devices: openDevices.toList()..sort(),
          ),
        );
      }
    } on FileSystemException {
      return null;
    }

    processes.sort((a, b) {
      final byName = a.name.compareTo(b.name);
      return byName != 0 ? byName : a.pid.compareTo(b.pid);
    });
    final reporting = switch ((includeMemory, readDrmClient, readPciAddress)) {
      (false, _, _) when processes.isNotEmpty => GpuProcessReporting.reported,
      (true, _, true) => GpuProcessReporting.reported,
      (true, true, false) => GpuProcessReporting.notReported,
      _ => GpuProcessReporting.noClients,
    };
    return GpuProcessScan(processes: processes, reporting: reporting);
  }

  Future<Set<String>> _deviceNodes(
    String pciAddress, {
    required bool includeDriver,
  }) async {
    final nodes = <String>{};
    final drm = Directory('$pciPath/devices/$pciAddress/drm');
    if (await drm.exists()) {
      await for (final entry in drm.list(followLinks: false)) {
        final name = _basename(entry.path);
        if (_drmNode.hasMatch(name)) nodes.add('$devicePath/dri/$name');
      }
    }
    if (!includeDriver) return nodes;

    // A single bound NVIDIA GPU and driver node let us match the node to PCI.
    final driver = Directory('$pciPath/drivers/nvidia');
    if (!await driver.exists()) return nodes;
    final boundGpus = await driver
        .list(followLinks: false)
        .map((entry) => _basename(entry.path))
        .where(_pciAddress.hasMatch)
        .toList();
    if (boundGpus.length != 1 || boundGpus.single != pciAddress) return nodes;

    final driverNodes = await Directory(devicePath)
        .list(followLinks: false)
        .map((entry) => entry.path)
        .where((path) => _driverNode.hasMatch(_basename(path)))
        .toList();
    if (driverNodes.length == 1) nodes.add(driverNodes.single);
    return nodes;
  }

  int _memoryKib(String line) {
    final match = RegExp(r'^drm-memory-[^:]+:\s*(\d+)\s*(KiB|MiB)\s*$')
        .firstMatch(line.trim());
    if (match == null) return 0;
    final amount = int.tryParse(match.group(1)!) ?? 0;
    return match.group(2) == 'MiB' ? amount * 1024 : amount;
  }

  String _valueOf(String line) => line.substring(line.indexOf(':') + 1).trim();

  Future<String> _readName(int pid) async {
    final process = '$procPath/$pid';
    for (final path in ['$process/comm', '$process/cmdline']) {
      try {
        final bytes = await File(path).readAsBytes();
        final value = utf8.decode(bytes, allowMalformed: true).trim();
        if (value.isEmpty) continue;
        final name = _basename(value.split('\u0000').first);
        return await _unwrapName(process, name);
      } on FileSystemException {
        continue;
      }
    }
    return 'Unknown process';
  }

  Future<String> _unwrapName(String process, String name) async {
    if (!name.startsWith('.')) return name;
    const suffix = '-wrapped';
    if (name.endsWith(suffix)) {
      return name.substring(1, name.length - suffix.length);
    }
    try {
      // The executable can supply the full Nix wrapper name when comm truncates it.
      final executable = _basename(await Link('$process/exe').target());
      if (executable.startsWith(name) && executable.endsWith(suffix)) {
        return executable.substring(1, executable.length - suffix.length);
      }
    } on FileSystemException {
      return name;
    }
    return name;
  }

  static String _basename(String path) => path.split('/').last;
}
