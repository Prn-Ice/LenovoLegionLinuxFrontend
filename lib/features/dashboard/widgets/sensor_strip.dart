import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/metric_gauge.dart';
import '../../../core/widgets/metric_tile.dart';
import '../../sensors/models/live_sensor_snapshot.dart';

/// Telemetry hero for the dashboard: prominent temperature/fan gauges plus
/// utilisation and secondary metric tiles, all derived from the shared
/// [LiveSensorSnapshot]. [accent] follows the current power mode.
class SensorStrip extends StatelessWidget {
  const SensorStrip({super.key, required this.snapshot, required this.accent});

  final LiveSensorSnapshot snapshot;
  final Color accent;

  static const double _tempCritical = 90;

  @override
  Widget build(BuildContext context) {
    final gauges = <Widget>[
      if (snapshot.cpuTempC != null)
        _gauge(
          snapshot.cpuTempC,
          30,
          100,
          'CPU',
          '°C',
          critical: _tempCritical,
        ),
      if (snapshot.gpuTempC != null)
        _gauge(
          snapshot.gpuTempC,
          30,
          100,
          snapshot.gpuIsDiscrete ? 'dGPU' : 'iGPU',
          '°C',
          critical: _tempCritical,
        ),
      if (snapshot.fan1Rpm != null)
        _gauge(snapshot.fan1Rpm!.toDouble(), 0, 6000, 'CPU fan', ''),
      if (snapshot.gpuFanRpm != null)
        _gauge(snapshot.gpuFanRpm!.toDouble(), 0, 6000, 'GPU fan', ''),
    ];

    final tiles = <Widget>[
      if (snapshot.cpuUtilPercent != null)
        _tile('CPU load', snapshot.cpuUtilPercent, '%'),
      if (snapshot.gpuUtilPercent != null)
        _tile('GPU load', snapshot.gpuUtilPercent, '%'),
      if (snapshot.gpuVramUsedGb != null && snapshot.gpuVramTotalGb != null)
        MetricTile(
          label: 'VRAM',
          value: snapshot.gpuVramUsedGb,
          min: 0,
          max: snapshot.gpuVramTotalGb!,
          unit: ' / ${snapshot.gpuVramTotalGb!.toStringAsFixed(0)} GB',
          accent: accent,
          fractionDigits: 1,
        ),
      if (snapshot.gpuPowerDrawW != null)
        _tile('GPU power', snapshot.gpuPowerDrawW, ' W', showBar: false),
    ];

    if (gauges.isEmpty && tiles.isEmpty) {
      return const YaruSection(child: Text('Sensor data unavailable.'));
    }

    return YaruSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (gauges.isNotEmpty)
            Wrap(
              spacing: 20,
              runSpacing: 16,
              alignment: WrapAlignment.spaceEvenly,
              children: gauges,
            ),
          if (gauges.isNotEmpty && tiles.isNotEmpty) const SizedBox(height: 20),
          for (final tile in tiles)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: tile),
          _SecondaryLine(snapshot: snapshot),
        ],
      ),
    );
  }

  Widget _gauge(
    double? value,
    double min,
    double max,
    String label,
    String unit, {
    double? critical,
  }) => MetricGauge(
    value: value,
    min: min,
    max: max,
    label: label,
    unit: unit,
    accent: accent,
    criticalThreshold: critical,
    size: 116,
  );

  Widget _tile(
    String label,
    double? value,
    String unit, {
    bool showBar = true,
  }) => MetricTile(
    label: label,
    value: value,
    unit: unit,
    accent: accent,
    showBar: showBar,
  );
}

/// Compact one-line readout for the lower-priority sensors.
class _SecondaryLine extends StatelessWidget {
  const _SecondaryLine({required this.snapshot});

  final LiveSensorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final items = <String>[];
    if (snapshot.motherboardTempC != null) {
      items.add('Board ${snapshot.motherboardTempC!.toStringAsFixed(0)}°C');
    }
    if (snapshot.batteryPercent != null) {
      final state = snapshot.batteryCharging == true
          ? 'charging'
          : 'discharging';
      final draw = snapshot.batteryPowerDrawW != null
          ? ' ${snapshot.batteryPowerDrawW!.toStringAsFixed(0)}W'
          : '';
      items.add('Battery ${snapshot.batteryPercent}% $state$draw');
    }
    if (snapshot.diskTempC != null) {
      items.add('Disk ${snapshot.diskTempC!.toStringAsFixed(0)}°C');
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        items.join('   ·   '),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
