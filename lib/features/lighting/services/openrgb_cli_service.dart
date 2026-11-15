import 'dart:convert';
import 'dart:io';

import '../../../core/models/app_failure.dart';
import '../models/rgb_lighting_device.dart';

typedef OpenRgbProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

enum _OpenRgbWrite { apply, loadProfile, saveProfile }

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

/// Runs OpenRGB commands to discover devices and change keyboard lighting.
/// Each call starts a process and checks its exit status.
class OpenRgbCliService {
  const OpenRgbCliService({
    this.executable = 'openrgb',
    OpenRgbProcessRunner processRunner = Process.run,
  }) : _processRunner = processRunner;

  final String executable;
  final OpenRgbProcessRunner _processRunner;

  /// Whether OpenRGB can list devices successfully.
  Future<bool> isAvailable() async {
    try {
      final result = await _processRunner(executable, ['--list-devices']);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// Lists RGB devices the OpenRGB server/host exposes.
  Future<List<RgbLightingDevice>> listDevices() async {
    final ProcessResult result;
    try {
      result = await _processRunner(executable, ['--list-devices']);
    } on ProcessException {
      // OpenRGB is optional: the native Spectrum backend may still be usable.
      return const [];
    }
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
    await _runWrite(
      openRgbApplyArgs(
        device: device,
        zone: zone,
        mode: mode,
        colorsHex: colorsHex,
        brightness: brightness,
        speed: speed,
      ),
      operation: _OpenRgbWrite.apply,
    );
  }

  /// Loads a saved OpenRGB profile.
  Future<void> loadProfile(String name) async {
    await _runWrite(['-p', name], operation: _OpenRgbWrite.loadProfile);
  }

  /// Saves the current configuration to a named profile.
  Future<void> saveProfile(String name) async {
    await _runWrite(['-sp', name], operation: _OpenRgbWrite.saveProfile);
  }

  Future<void> _runWrite(
    List<String> arguments, {
    required _OpenRgbWrite operation,
  }) async {
    final command = 'Command: ${jsonEncode([executable, ...arguments])}';
    final ProcessResult result;
    try {
      result = await _processRunner(executable, arguments);
    } on ProcessException catch (error) {
      throw AppFailure(
        'OpenRGB could not start. Check that OpenRGB is installed and available, then retry.',
        kind: AppFailureKind.unavailable,
        details: '$command\n$error',
      );
    }
    if (result.exitCode == 0) return;

    final message = switch (operation) {
      _OpenRgbWrite.apply =>
        'OpenRGB could not apply keyboard lighting. The keyboard may be partly updated. Check the OpenRGB connection and selected device, then retry.',
      _OpenRgbWrite.loadProfile =>
        'OpenRGB could not load the profile. The keyboard may be partly updated. Check the profile in OpenRGB, then retry.',
      _OpenRgbWrite.saveProfile =>
        'OpenRGB could not save the profile. The profile file may be incomplete. Check the destination in OpenRGB, then save again.',
    };
    throw AppFailure(
      message,
      kind: AppFailureKind.commandFailed,
      details:
          '$command\nExit code: ${result.exitCode}\n'
          'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
  }
}
