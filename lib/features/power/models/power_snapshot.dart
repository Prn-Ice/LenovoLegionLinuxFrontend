import '../../../core/models/cpu_policy_snapshot.dart';
import '../../../core/models/power_profiles_daemon_snapshot.dart';
import 'power_limit.dart';
import 'power_mode.dart';

class PowerSnapshot {
  const PowerSnapshot({
    required this.currentMode,
    required this.availableModes,
    required this.powerLimits,
    required this.cpuOverclockEnabled,
    required this.gpuOverclockEnabled,
    this.onPowerSupply,
    this.daemonSnapshot,
    this.cpuPolicy,
  });

  final PowerMode? currentMode;
  final List<PowerMode> availableModes;
  final List<PowerLimitReading> powerLimits;
  final bool? cpuOverclockEnabled;
  final bool? gpuOverclockEnabled;
  final bool? onPowerSupply;
  final PowerProfilesDaemonSnapshot? daemonSnapshot;
  final CpuPolicySnapshot? cpuPolicy;
}
