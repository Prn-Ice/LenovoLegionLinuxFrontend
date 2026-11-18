import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/metric_gauge.dart';
import '../../../core/widgets/metric_tile.dart';
import '../../../core/widgets/surface_card.dart';
import '../../sensors/models/live_sensor_snapshot.dart';
import '../models/dashboard_metric.dart';

/// Dashboard temperatures, fan speeds, and usage from [LiveSensorSnapshot].
class SensorStrip extends StatelessWidget {
  const SensorStrip({
    super.key,
    required this.snapshot,
    required this.accent,
    this.hiddenMetrics = const {},
  });

  final LiveSensorSnapshot snapshot;
  final Color accent;
  final Set<DashboardMetric> hiddenMetrics;

  bool _show(DashboardMetric metric, Object? value) =>
      value != null && !hiddenMetrics.contains(metric);

  static const double _tempCritical = 90;

  @override
  Widget build(BuildContext context) {
    final gauges = <Widget>[
      if (_show(DashboardMetric.cpuTemperature, snapshot.cpuTempC))
        _GaugeCard(
          value: snapshot.cpuTempC,
          min: 0,
          max: 100,
          label: 'CPU temp',
          unit: '°',
          fractionDigits: 1,
          accent: accent,
          critical: _tempCritical,
        ),
      if (_show(DashboardMetric.igpuTemperature, snapshot.igpu?.tempC))
        _GaugeCard(
          value: snapshot.igpu?.tempC,
          min: 0,
          max: 100,
          label: 'iGPU temp',
          unit: '°',
          fractionDigits: 1,
          accent: accent,
          critical: _tempCritical,
        ),
      if (_show(DashboardMetric.dgpuTemperature, snapshot.dgpu?.tempC))
        _GaugeCard(
          value: snapshot.dgpu?.tempC,
          min: 0,
          max: 100,
          label: 'dGPU temp',
          unit: '°',
          fractionDigits: 1,
          accent: accent,
          critical: _tempCritical,
        ),
      if (_show(DashboardMetric.cpuFan, snapshot.fan1Rpm))
        _GaugeCard(
          value: snapshot.fan1Rpm!.toDouble(),
          min: 0,
          max: (snapshot.fan1MaxRpm ?? 6000).toDouble(),
          label: 'CPU fan (RPM)',
          accent: accent,
        ),
      if (_show(DashboardMetric.gpuFan, snapshot.fan2Rpm))
        _GaugeCard(
          value: snapshot.fan2Rpm!.toDouble(),
          min: 0,
          max: (snapshot.fan2MaxRpm ?? 6000).toDouble(),
          label: 'GPU fan (RPM)',
          accent: accent,
        ),
      if (_show(DashboardMetric.diskTemperature, snapshot.diskTempC))
        _GaugeCard(
          value: snapshot.diskTempC,
          min: 0,
          max: 100,
          label: 'Disk temp',
          unit: '°',
          fractionDigits: 1,
          accent: accent,
          critical: 75,
        ),
    ];

    final tiles = <Widget>[
      if (_show(DashboardMetric.cpuUsage, snapshot.cpuUtilPercent))
        _tile('CPU usage', snapshot.cpuUtilPercent, '%'),
      if (_show(DashboardMetric.igpuUsage, snapshot.igpu?.usagePercent))
        _tile('iGPU usage', snapshot.igpu?.usagePercent, '%'),
      if (_show(DashboardMetric.dgpuUsage, snapshot.dgpu?.usagePercent))
        _tile('dGPU usage', snapshot.dgpu?.usagePercent, '%'),
      if (_show(DashboardMetric.vram, snapshot.dgpu?.vramUsedGb) &&
          (snapshot.dgpu?.vramTotalGb ?? 0) > 0)
        MetricTile(
          label: 'dGPU VRAM',
          value: snapshot.dgpu?.vramUsedGb,
          min: 0,
          max: snapshot.dgpu!.vramTotalGb!,
          unit: ' / ${snapshot.dgpu!.vramTotalGb!.toStringAsFixed(0)} GB',
          accent: accent,
          fractionDigits: 1,
        ),
    ];

    final secondary = <String>[
      if (_show(DashboardMetric.systemTemperature, snapshot.motherboardTempC))
        'System ${snapshot.motherboardTempC!.toStringAsFixed(1)}°C',
    ];
    if (gauges.isEmpty && tiles.isEmpty && secondary.isEmpty) {
      return SurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            hiddenMetrics.isEmpty
                ? 'Sensor data unavailable.'
                : 'No readings to show. Choose readings in Settings.',
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (gauges.isNotEmpty)
          Wrap(spacing: 12, runSpacing: 12, children: gauges),
        if (gauges.isNotEmpty && (tiles.isNotEmpty || secondary.isNotEmpty))
          const SizedBox(height: 12),
        if (tiles.isNotEmpty || secondary.isNotEmpty)
          SurfaceCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                for (final tile in tiles)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: tile,
                  ),
                if (secondary.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: tiles.isEmpty ? 0 : 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          for (final item in secondary)
                            Text(
                              item,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _tile(String label, double? value, String unit) =>
      MetricTile(label: label, value: value, unit: unit, accent: accent);
}

/// A single gauge card: the radial gauge centered in a bordered surface with
/// its label below.
class _GaugeCard extends StatelessWidget {
  const _GaugeCard({
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.accent,
    this.unit = '',
    this.critical,
    this.fractionDigits = 0,
  });

  final double? value;
  final double min;
  final double max;
  final String label;
  final Color accent;
  final String unit;
  final double? critical;
  final int fractionDigits;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 176,
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MetricGauge(
              value: value,
              min: min,
              max: max,
              unit: unit,
              accent: accent,
              criticalThreshold: critical,
              fractionDigits: fractionDigits,
              size: 116,
            ),
            const SizedBox(height: 14),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}
