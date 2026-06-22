import 'package:hive_ce/hive.dart';

import '../models/rgb_lighting_snapshot.dart';

/// Persists the per-key RGB config to a Hive box so it survives page navigation
/// and app restarts — the keyboard can't report its own per-key colors, so the
/// app remembers them and re-applies on launch.
class RgbLightingStore {
  RgbLightingStore(this._box);

  final Box? _box;
  static const _key = 'config';

  /// The last saved snapshot, or null if nothing is stored / it's unreadable.
  RgbLightingSnapshot? load() {
    final raw = _box?.get(_key);
    if (raw is! Map) return null;
    return RgbLightingSnapshot.fromMap(Map<String, dynamic>.from(raw));
  }

  Future<void> save(RgbLightingSnapshot snapshot) async {
    await _box?.put(_key, snapshot.toMap());
  }
}
