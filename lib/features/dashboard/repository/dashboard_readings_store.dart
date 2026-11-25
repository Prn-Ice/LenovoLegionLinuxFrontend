import 'package:hive_ce/hive.dart';

import '../models/dashboard_metric.dart';

class DashboardReadingsStore {
  DashboardReadingsStore(this._box);

  final Box<dynamic> _box;
  static const key = 'dashboardHiddenMetrics';

  Set<DashboardMetric> load() {
    final raw = _box.get(key);
    if (raw is! List) return DashboardMetric.defaultHidden;
    return {
      for (final metric in DashboardMetric.values)
        if (raw.contains(metric.name)) metric,
    };
  }

  Future<void> save(Set<DashboardMetric> hidden) =>
      _box.put(key, hidden.map((metric) => metric.name).toList());
}
