import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';
import '../../sensors/models/live_sensor_snapshot.dart';

class SensorStrip extends StatelessWidget {
  const SensorStrip({super.key, required this.snapshot});

  final LiveSensorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return YaruSection(
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _CpuColumn(snapshot: snapshot)),
              const SizedBox(width: 16),
              Expanded(child: _GpuColumn(snapshot: snapshot)),
            ],
          ),
          const SizedBox(height: 8),
          _SecondaryRow(snapshot: snapshot),
        ],
      ),
    );
  }
}

class _CpuColumn extends StatelessWidget {
  const _CpuColumn({required this.snapshot});
  final LiveSensorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _SensorColumn(
      name: snapshot.cpuName ?? 'CPU',
      rows: [
        if (snapshot.cpuUtilPercent != null)
          _SensorRow('Utilisation', '${snapshot.cpuUtilPercent!.toStringAsFixed(0)} %'),
        if (snapshot.cpuClockGhz != null)
          _SensorRow('Core Clock', '${snapshot.cpuClockGhz!.toStringAsFixed(2)} GHz'),
        if (snapshot.cpuTempC != null)
          _SensorRow('Temperature', '${snapshot.cpuTempC!.toStringAsFixed(0)} °C',
            highlight: _tempColor(context, snapshot.cpuTempC!)),
        if (snapshot.fan1Rpm != null)
          _SensorRow('Fan', '${snapshot.fan1Rpm} RPM'),
      ],
    );
  }
}

class _GpuColumn extends StatelessWidget {
  const _GpuColumn({required this.snapshot});
  final LiveSensorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final label = snapshot.gpuIsDiscrete ? 'dGPU' : 'iGPU';
    return _SensorColumn(
      name: snapshot.gpuName ?? label,
      rows: [
        if (snapshot.gpuUtilPercent != null)
          _SensorRow('Utilisation', '${snapshot.gpuUtilPercent!.toStringAsFixed(0)} %'),
        if (snapshot.gpuClockGhz != null)
          _SensorRow('Core Clock', '${snapshot.gpuClockGhz!.toStringAsFixed(2)} GHz'),
        if (snapshot.gpuTempC != null)
          _SensorRow('Temperature', '${snapshot.gpuTempC!.toStringAsFixed(0)} °C',
            highlight: _tempColor(context, snapshot.gpuTempC!)),
        if (snapshot.gpuFanRpm != null)
          _SensorRow('Fan', '${snapshot.gpuFanRpm} RPM'),
        if (snapshot.gpuVramUsedGb != null && snapshot.gpuVramTotalGb != null)
          _SensorRow('VRAM',
            '${snapshot.gpuVramUsedGb!.toStringAsFixed(1)} / ${snapshot.gpuVramTotalGb!.toStringAsFixed(0)} GB'),
        if (snapshot.gpuPowerDrawW != null)
          _SensorRow('Power', '${snapshot.gpuPowerDrawW!.toStringAsFixed(0)} W'),
      ],
    );
  }
}

class _SensorColumn extends StatelessWidget {
  const _SensorColumn({required this.name, required this.rows});
  final String name;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        ...rows,
      ],
    );
  }
}

class _SensorRow extends StatelessWidget {
  const _SensorRow(this.label, this.value, {this.highlight});
  final String label;
  final String value;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          Text(value,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: highlight,
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryRow extends StatelessWidget {
  const _SecondaryRow({required this.snapshot});
  final LiveSensorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final items = <String>[];
    if (snapshot.motherboardTempC != null) {
      items.add('Motherboard  ${snapshot.motherboardTempC!.toStringAsFixed(0)}°C');
    }
    if (snapshot.batteryPercent != null) {
      final state = snapshot.batteryCharging == true ? 'Charging' : 'Discharging';
      final draw = snapshot.batteryPowerDrawW != null
          ? '  ${snapshot.batteryPowerDrawW!.toStringAsFixed(0)}W'
          : '';
      items.add('Battery  ${snapshot.batteryPercent}%  $state$draw');
    }
    if (snapshot.diskTempC != null) {
      items.add('Disk  ${snapshot.diskTempC!.toStringAsFixed(0)}°C');
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Text(
      items.join('   ·   '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
      ),
    );
  }
}

Color? _tempColor(BuildContext context, double tempC) {
  if (tempC >= 85) return Colors.red;
  if (tempC >= 70) return Colors.orange;
  return null;
}
