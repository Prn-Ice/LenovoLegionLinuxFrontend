import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/metric_gauge.dart';
import '../../../core/widgets/metric_tile.dart';
import '../../sensors/models/live_sensor_snapshot.dart';

/// Telemetry hero for the dashboard: a row of gauge cards (temperatures + fan
/// speeds) above a load card with utilisation bars and power, all from the
/// shared [LiveSensorSnapshot]. [accent] follows the current power mode.
class SensorStrip extends StatelessWidget {
  const SensorStrip({super.key, required this.snapshot, required this.accent});

  final LiveSensorSnapshot snapshot;
  final Color accent;

  static const double _tempCritical = 90;

  @override
  Widget build(BuildContext context) {
    final gauges = <Widget>[
      if (snapshot.cpuTempC != null)
        _GaugeCard(
          value: snapshot.cpuTempC,
          min: 30,
          max: 100,
          label: 'CPU temp',
          unit: '°',
          accent: accent,
          critical: _tempCritical,
        ),
      if (snapshot.gpuTempC != null)
        _GaugeCard(
          value: snapshot.gpuTempC,
          min: 30,
          max: 100,
          label: snapshot.gpuIsDiscrete ? 'dGPU temp' : 'iGPU temp',
          unit: '°',
          accent: accent,
          critical: _tempCritical,
        ),
      if (snapshot.fan1Rpm != null)
        _GaugeCard(
          value: snapshot.fan1Rpm!.toDouble(),
          min: 0,
          max: 6000,
          label: 'CPU fan',
          accent: accent,
        ),
      if (snapshot.gpuFanRpm != null)
        _GaugeCard(
          value: snapshot.gpuFanRpm!.toDouble(),
          min: 0,
          max: 6000,
          label: 'GPU fan',
          accent: accent,
        ),
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
      return YaruBorderContainer(
        padding: const EdgeInsets.all(16),
        child: const Center(child: Text('Sensor data unavailable.')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (gauges.isNotEmpty)
          Wrap(spacing: 12, runSpacing: 12, children: gauges),
        if (gauges.isNotEmpty && tiles.isNotEmpty) const SizedBox(height: 12),
        if (tiles.isNotEmpty)
          YaruBorderContainer(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                for (final tile in tiles)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: tile,
                  ),
                _SecondaryLine(snapshot: snapshot),
              ],
            ),
          ),
      ],
    );
  }

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
  });

  final double? value;
  final double min;
  final double max;
  final String label;
  final Color accent;
  final String unit;
  final double? critical;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: 176,
      child: YaruBorderContainer(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
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
              size: 120,
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          items.join('   ·   '),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
