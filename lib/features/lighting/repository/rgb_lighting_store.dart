import 'package:hive_ce/hive.dart';

import '../models/rgb_lighting_snapshot.dart';

/// Persists the per-key RGB config to a Hive box so it survives page navigation
/// and app restarts — the keyboard can't report its own per-key colors, so the
/// app remembers them and re-applies on launch.
class RgbLightingStore {
  RgbLightingStore(this._box);

  final Box? _box;
  static const _key = 'config';
  static const _namesKey = 'profileNames';
  String _profileKey(String name) => 'profile:$name';

  /// The last saved snapshot, or null if nothing is stored / it's unreadable.
  RgbLightingSnapshot? load() => _readSnapshot(_key);

  Future<void> save(RgbLightingSnapshot snapshot) async {
    await _box?.put(_key, snapshot.toMap());
  }

  /// The saved named profiles, in creation order.
  List<String> profileNames() {
    final raw = _box?.get(_namesKey);
    return raw is List ? raw.cast<String>() : const [];
  }

  RgbLightingSnapshot? loadProfile(String name) =>
      _readSnapshot(_profileKey(name));

  Future<void> saveProfile(String name, RgbLightingSnapshot snapshot) async {
    await _box?.put(_profileKey(name), snapshot.toMap());
    final names = profileNames();
    if (!names.contains(name)) await _box?.put(_namesKey, [...names, name]);
  }

  Future<void> deleteProfile(String name) async {
    await _box?.delete(_profileKey(name));
    await _box?.put(_namesKey, profileNames().where((n) => n != name).toList());
  }

  RgbLightingSnapshot? _readSnapshot(String key) {
    final raw = _box?.get(key);
    if (raw is! Map) return null;
    return RgbLightingSnapshot.fromMap(Map<String, dynamic>.from(raw));
  }
}
