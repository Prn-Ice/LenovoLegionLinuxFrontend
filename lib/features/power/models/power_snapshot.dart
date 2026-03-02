import 'power_limit.dart';
import 'power_mode.dart';

class PowerSnapshot {
  const PowerSnapshot({
    required this.currentMode,
    required this.availableModes,
    required this.powerLimits,
  });

  final PowerMode? currentMode;
  final List<PowerMode> availableModes;
  final List<PowerLimitReading> powerLimits;
}
