import 'package:hive_ce/hive.dart';

import '../../../core/models/control_mode.dart';

/// The saved choice is read by main before constructing the app's providers.
class ControlModeStore {
  ControlModeStore(this._box);
  final Box<dynamic> _box;
  static const key = 'controlMode';

  ControlMode load() {
    final value = _box.get(key);
    return ControlMode.values.where((mode) => mode.name == value).firstOrNull ??
        ControlMode.installedService;
  }

  Future<void> save(ControlMode mode) => _box.put(key, mode.name);
}
