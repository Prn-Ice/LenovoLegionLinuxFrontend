import 'dart:ui';

import 'package:legion_frontend/features/automation/models/automation_config.dart';
import 'package:legion_frontend/features/automation/repository/automation_repository.dart';
import 'package:legion_frontend/features/dashboard/models/dashboard_snapshot.dart';
import 'package:legion_frontend/features/dashboard/models/system_status.dart';
import 'package:legion_frontend/features/dashboard/repository/dashboard_repository.dart';
import 'package:legion_frontend/features/lighting/models/rgb_lighting_device.dart';
import 'package:legion_frontend/features/lighting/models/rgb_lighting_snapshot.dart';
import 'package:legion_frontend/features/lighting/repository/rgb_lighting_repository.dart';
import 'package:legion_frontend/features/lighting/repository/rgb_lighting_store.dart';
import 'package:legion_frontend/features/lighting/repository/spectrum_rgb_repository.dart';

class MemoryAssignments extends AutomationRepository {
  AutomationConfig config = AutomationConfig.defaults();
  @override
  Future<AutomationConfig> loadConfig() async => config;
  @override
  Future<void> saveConfig(AutomationConfig value) async => config = value;
}

class ObservedPowerMode implements DashboardRepository {
  String? mode = 'balanced';
  @override
  Future<DashboardSnapshot> loadSnapshot() async =>
      DashboardSnapshot.initial().copyWith(
        status: SystemStatus(updatedAt: DateTime.utc(2026), powerProfile: mode),
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RecordingKeyboard extends RgbLightingRepository {
  final writes = <List<Color>>[];
  static const device = RgbLightingDevice(
    index: 0,
    name: 'Test keyboard',
    type: 'Keyboard',
    modes: ['Direct', 'Static'],
    leds: ['A'],
  );
  @override
  Future<RgbLightingDevice?> loadKeyboard() async => device;
  @override
  Future<void> applyDirect(
    RgbLightingDevice device,
    List<Color> colors, {
    int? brightness,
  }) async => writes.add(colors);
}

class NoNativeKeyboard extends SpectrumRgbRepository {
  @override
  bool get isAvailable => false;
}

class MemoryLightingProfiles extends RgbLightingStore {
  MemoryLightingProfiles() : super(null);
  final profiles = <String, RgbLightingSnapshot>{
    'Night': const RgbLightingSnapshot(
      keyColors: [Color(0xFF0000FF)],
      selectedColor: Color(0xFF0000FF),
      brightness: 40,
      activeMode: 'Direct',
      effects: [],
    ),
    'Gaming': const RgbLightingSnapshot(
      keyColors: [Color(0xFFFF0000)],
      selectedColor: Color(0xFFFF0000),
      brightness: 90,
      activeMode: 'Direct',
      effects: [],
    ),
  };
  @override
  List<String> profileNames() => profiles.keys.toList();
  @override
  RgbLightingSnapshot? loadProfile(String name) => profiles[name];
  @override
  Future<void> deleteProfile(String name) async => profiles.remove(name);
}
