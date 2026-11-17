import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/metric_gauge.dart';
import '../../../core/widgets/metric_tile.dart';
import '../../../core/widgets/metric_text.dart';
import '../../../core/widgets/surface_card.dart';
import '../../sensors/models/live_sensor_snapshot.dart';

/// Telemetry hero for the dashboard: a row of gauge cards (temperatures + fan
/// speeds) above a load card with utilisation bars, all from the
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
          fractionDigits: 1,
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
          fractionDigits: 1,
          accent: accent,
          critical: _tempCritical,
        ),
      if (snapshot.fan1Rpm != null)
        _FanCard(
          value: snapshot.fan1Rpm!.toDouble(),
          max: snapshot.fan1MaxRpm,
          label: 'CPU fan (RPM)',
          accent: accent,
        ),
      if (snapshot.fan2Rpm != null)
        _FanCard(
          value: snapshot.fan2Rpm!.toDouble(),
          max: snapshot.fan2MaxRpm,
          label: 'GPU fan (RPM)',
          accent: accent,
        ),
      if (snapshot.fan3Rpm != null)
        _FanCard(
          value: snapshot.fan3Rpm!.toDouble(),
          max: snapshot.fan3MaxRpm,
          label: 'Fan 3 (RPM)',
          accent: accent,
        ),
      if (snapshot.diskTempC != null)
        _GaugeCard(
          value: snapshot.diskTempC,
          min: 20,
          max: 90,
          label: 'Disk temp',
          unit: '°',
          fractionDigits: 1,
          accent: accent,
          critical: 75,
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
    ];

    if (gauges.isEmpty && tiles.isEmpty) {
      return SurfaceCard(
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
          SurfaceCard(
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

  Widget _tile(String label, double? value, String unit) =>
      MetricTile(label: label, value: value, unit: unit, accent: accent);
}

/// A single gauge card: the radial gauge centered in a bordered surface with
/// its label below.
class _FanCard extends StatelessWidget {
  const _FanCard({
    required this.value,
    required this.max,
    required this.label,
    required this.accent,
  });

  final double value;
  final int? max;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final validMax = max != null && max! > 0 ? max!.toDouble() : null;
    if (validMax != null) {
      return _GaugeCard(
        value: value,
        min: 0,
        max: validMax,
        label: label,
        accent: accent,
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: ValueKey('$label-numeric'),
      label: '$label: ${value.toStringAsFixed(0)} RPM',
      child: SizedBox(
        width: 176,
        child: SurfaceCard(
          padding: const EdgeInsets.fromLTRB(16, 38, 16, 34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value.toStringAsFixed(0),
                      style: monoGaugeStyle(116, scheme.onSurface),
                    ),
                    TextSpan(text: ' RPM', style: monoUnitStyle(scheme)),
                  ],
                ),
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
      ),
    );
  }
}

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

/// Compact one-line readout for the lower-priority sensors.
class _SecondaryLine extends StatelessWidget {
  const _SecondaryLine({required this.snapshot});

  final LiveSensorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final items = <String>[];
    if (snapshot.batteryPercent != null) {
      final state = snapshot.batteryCharging == true
          ? 'charging'
          : 'discharging';
      final draw = snapshot.batteryPowerDrawW != null
          ? ' ${snapshot.batteryPowerDrawW!.toStringAsFixed(0)}W'
          : '';
      items.add('Battery ${snapshot.batteryPercent}% $state$draw');
    }
    if (snapshot.motherboardTempC != null) {
      items.add('System ${snapshot.motherboardTempC!.toStringAsFixed(1)}°C');
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          items.join('   ·   '),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
