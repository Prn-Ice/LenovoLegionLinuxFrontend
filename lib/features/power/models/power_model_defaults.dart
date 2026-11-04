/// Recorded CPU/GPU power and temperature limits shown as "Hardware default"
/// labels and slider markers on the Power page. Each product/BIOS pair maps
/// power-limit IDs to values in watts or °C. Capture details are in
/// docs/power-defaults-evidence.md.
const _referenceLimits = <(String, String), Map<String, int>>{
  ('82Y4', 'M1CN48WW'): {
    'cpu_longterm': 54,
    'cpu_shortterm': 54,
    'cpu_peak': 65,
    'cpu_cross_loading': 45,
    'cpu_temperature': 100,
    'gpu_ctgp': 60,
    'gpu_temperature': 87,
    'gpu_power_target_offset': 45,
  },
};

Map<String, int> powerReferenceLimitsFor({
  required String? productName,
  required String? biosVersion,
}) => _referenceLimits[(productName, biosVersion)] ?? const {};
