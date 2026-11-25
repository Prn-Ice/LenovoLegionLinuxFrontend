import 'dart:io';

import '../models/gpu_process.dart';
import '../models/gpu_process_scan.dart';

/// Reads the kernel's per-process DRM client statistics from procfs.
class DrmProcessService {
  DrmProcessService({
    this.procPath = '/proc',
    this.minimumInterval = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String procPath;

  /// The scan walks every readable process, so the page reuses a recent result
  /// instead of repeating that work on each two-second sensor poll.
  final Duration minimumInterval;
  final DateTime Function() _clock;

  String? _cachedAddress;
  DateTime? _lastScan;
  GpuProcessScan? _cachedScan;

  /// Finds processes whose DRM client reports [pciAddress].
  ///
  /// Only fdinfo files this user can read contribute to the result. A kernel
  /// or driver that omits `drm-pdev` cannot map a client to a GPU; the scan
  /// reports that state instead of treating it as an empty process list.
  /// Returns null when procfs itself cannot be read.
  Future<GpuProcessScan?> readProcesses(String pciAddress) async {
    final now = _clock();
    final lastScan = _lastScan;
    if (lastScan != null &&
        _cachedAddress == pciAddress &&
        now.difference(lastScan) < minimumInterval) {
      return _cachedScan;
    }

    final scan = await _scan(pciAddress);
    _cachedAddress = pciAddress;
    _lastScan = now;
    _cachedScan = scan;
    return scan;
  }

  Future<GpuProcessScan?> _scan(String pciAddress) async {
    final memoryByPid = <int, int>{};
    var readDrmClient = false;
    var readPciAddress = false;

    try {
      await for (final process in Directory(procPath).list()) {
        final pid = int.tryParse(process.path.split('/').last);
        if (pid == null) continue;

        try {
          await for (final fd in Directory('${process.path}/fd').list()) {
            try {
              if (!(await Link(fd.path).target()).startsWith('/dev/dri/')) {
                continue;
              }
              readDrmClient = true;

              final contents = await File(
                '${process.path}/fdinfo/${fd.path.split('/').last}',
              ).readAsString();
              final lines = contents.split('\n');

              var belongsToGpu = false;
              for (final line in lines) {
                if (!line.startsWith('drm-pdev:')) continue;
                readPciAddress = true;
                belongsToGpu = _valueOf(line) == pciAddress;
              }
              if (!belongsToGpu) continue;

              for (final line in lines) {
                if (!line.startsWith('drm-memory-')) continue;
                memoryByPid.update(
                  pid,
                  (total) => total + _memoryKib(line),
                  ifAbsent: () => _memoryKib(line),
                );
              }
              memoryByPid.putIfAbsent(pid, () => 0);
            } on FileSystemException {
              continue;
            }
          }
        } on FileSystemException {
          continue;
        }
      }
    } on FileSystemException {
      return null;
    }

    final reporting = switch ((readDrmClient, readPciAddress)) {
      (_, true) => GpuProcessReporting.reported,
      (true, false) => GpuProcessReporting.notReported,
      (false, false) => GpuProcessReporting.noClients,
    };

    final processes = <GpuProcess>[];
    for (final entry in memoryByPid.entries) {
      processes.add(
        GpuProcess(
          pid: entry.key,
          name: await _readName(entry.key),
          usedMemoryMib: entry.value ~/ 1024,
        ),
      );
    }
    processes.sort((a, b) {
      final byName = a.name.compareTo(b.name);
      return byName != 0 ? byName : a.pid.compareTo(b.pid);
    });

    return GpuProcessScan(processes: processes, reporting: reporting);
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
    for (final path in ['$procPath/$pid/comm', '$procPath/$pid/cmdline']) {
      try {
        final value = (await File(path).readAsString()).trim();
        if (value.isEmpty) continue;
        final firstPart = value.split('\u0000').first;
        return firstPart.split('/').last;
      } on FileSystemException {
        continue;
      }
    }
    return 'Unknown process';
  }
}
