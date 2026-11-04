import '../../fans/bloc/fans_state.dart';
import '../../power/bloc/power_state.dart';
import '../models/platform_event.dart';

/// Feed state emissions from explicit app-owned listeners. Initial values and
/// unknown readings establish/reset the baseline; they are not change events.
/// This class does not subscribe to features or send desktop notifications.
class ConfirmedPlatformChanges {
  String? _powerMode;
  bool? _fanBoost;

  PlatformEvent? observePower(PowerState state) {
    if (state.isLoading || state.isApplying || state.errorMessage != null) {
      return null;
    }
    final mode = state.currentMode;
    final previous = _powerMode;
    _powerMode = mode?.value;
    if (previous == null || mode == null || previous == mode.value) return null;
    return PowerModeChanged(label: mode.label, powerModeValue: mode.value);
  }

  PlatformEvent? observeFans(FansState state) {
    if (state.isLoading || state.isApplying || state.errorMessage != null) {
      return null;
    }
    final enabled = state.maximumFanSpeedEnabled;
    final previous = _fanBoost;
    _fanBoost = enabled;
    if (previous == null || enabled == null || previous == enabled) return null;
    return FanBoostChanged(
      enabled: enabled,
      powerModeValue: state.platformProfile,
    );
  }
}
