/// Reference readings from an 82Y4 laptop with M1CN48WW BIOS.
/// The Power page shows them beside current settings, in watts or °C.
/// They are not verified factory defaults and must not be used for restoration.
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
