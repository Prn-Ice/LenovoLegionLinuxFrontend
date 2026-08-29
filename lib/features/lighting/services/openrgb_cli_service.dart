import 'dart:io';

import '../models/rgb_lighting_device.dart';

/// Builds the `openrgb` CLI argument list for an apply operation. Pure so the
/// command construction (CLI order rules: `-z` after `-d`, mode/color after) is
/// unit-tested without spawning a process.
List<String> openRgbApplyArgs({
  required int device,
  int? zone,
  String? mode,
  List<String>? colorsHex,
  int? brightness,
  int? speed,
}) {
  final args = <String>['-d', '$device'];
  if (zone != null) args.addAll(['-z', '$zone']);
  if (mode != null && mode.isNotEmpty) args.addAll(['-m', mode]);
  if (colorsHex != null && colorsHex.isNotEmpty) {
    args.addAll(['-c', colorsHex.join(',')]);
  }
  if (brightness != null) args.addAll(['-b', '$brightness']);
  if (speed != null) args.addAll(['-s', '$speed']);
  return args;
}

/// Thin wrapper over the `openrgb` command-line tool. Drives OpenRGB (which
/// already supports the Legion keyboard) without depending on the buggy SDK
/// socket package. Each call spawns a short-lived process that talks to the
/// running OpenRGB server.
class OpenRgbCliService {
  const OpenRgbCliService({this.executable = 'openrgb'});

  final String executable;

  /// True when the `openrgb` binary runs and reports devices.
  Future<bool> isAvailable() async {
    try {
      final result = await Process.run(executable, ['--list-devices']);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// Lists RGB devices the OpenRGB server/host exposes.
  Future<List<RgbLightingDevice>> listDevices() async {
    final result = await Process.run(executable, ['--list-devices']);
    if (result.exitCode != 0) return const [];
    return parseOpenRgbDevices(result.stdout as String);
  }

  /// Applies a mode/colors/brightness/speed to a device (optionally one zone).
  Future<void> apply({
    required int device,
    int? zone,
    String? mode,
    List<String>? colorsHex,
    int? brightness,
    int? speed,
  }) async {
    await Process.run(
      executable,
      openRgbApplyArgs(
        device: device,
        zone: zone,
        mode: mode,
        colorsHex: colorsHex,
        brightness: brightness,
        speed: speed,
      ),
    );
  }

  /// Loads a saved OpenRGB profile (the design's "saved looks").
  Future<void> loadProfile(String name) async {
    await Process.run(executable, ['-p', name]);
  }

  /// Saves the current configuration to a named profile.
  Future<void> saveProfile(String name) async {
    await Process.run(executable, ['-sp', name]);
  }
}
