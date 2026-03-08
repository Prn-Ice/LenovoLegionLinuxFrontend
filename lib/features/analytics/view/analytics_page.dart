// lib/features/analytics/view/analytics_page.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bloc/analytics_event.dart';
import '../bloc/analytics_state.dart';
import '../models/sensor_record.dart';
import '../providers/analytics_provider.dart';

class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  @override
  void initState() {
    super.initState();
    ref.read(analyticsBlocProvider.bloc).add(const AnalyticsStarted());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analyticsBlocProvider);
    final latest = state.latest;
    final history = state.history;
    final bloc = ref.read(analyticsBlocProvider.bloc);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                state.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),

          // Live reading tiles
          _SensorTile(
            label: 'CPU Fan',
            value: latest?.fan1Rpm != null ? '${latest!.fan1Rpm} RPM' : '—',
            icon: Icons.air,
          ),
          _SensorTile(
            label: 'GPU Fan',
            value: latest?.fan2Rpm != null ? '${latest!.fan2Rpm} RPM' : '—',
            icon: Icons.air,
          ),
          _SensorTile(
            label: 'CPU Temp',
            value: latest?.cpuTempC != null
                ? '${latest!.cpuTempC!.toStringAsFixed(1)} °C'
                : '—',
            icon: Icons.thermostat,
          ),
          _SensorTile(
            label: 'GPU Temp',
            value: latest?.gpuTempC != null
                ? '${latest!.gpuTempC!.toStringAsFixed(1)} °C'
                : '—',
            icon: Icons.thermostat,
          ),

          const SizedBox(height: 16),

          // Time window picker
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<AnalyticsTimeWindow>(
              segments: AnalyticsTimeWindow.values
                  .map(
                    (w) => ButtonSegment<AnalyticsTimeWindow>(
                      value: w,
                      label: Text(w.label),
                    ),
                  )
                  .toList(),
              selected: {state.window},
              onSelectionChanged: (sel) =>
                  bloc.add(AnalyticsWindowChanged(sel.first)),
            ),
          ),

          const SizedBox(height: 24),

          if (history.length > 1) ...[
            _ChartSection(
              title: 'Temperature (°C)',
              child: _TemperatureChart(history: history),
            ),
            const SizedBox(height: 20),
            _ChartSection(
              title: 'Fan Speed (RPM)',
              child: _FanSpeedChart(history: history),
            ),
          ] else
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Collecting sensor data…'),
              ),
            ),
        ],
      ),
    );
  }
}

class _SensorTile extends StatelessWidget {
  const _SensorTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}

class _ChartSection extends StatelessWidget {
  const _ChartSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(height: 140, child: child),
      ],
    );
  }
}

class _TemperatureChart extends StatelessWidget {
  const _TemperatureChart({required this.history});

  final List<SensorRecord> history;

  List<FlSpot> _spots(double? Function(SensorRecord) pick) => history
      .asMap()
      .entries
      .where((e) => pick(e.value) != null)
      .map((e) => FlSpot(e.key.toDouble(), pick(e.value)!))
      .toList();

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: _spots((r) => r.cpuTempC),
            isCurved: true,
            color: Colors.orange,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: _spots((r) => r.gpuTempC),
            isCurved: true,
            color: Colors.blue,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
      ),
    );
  }
}

class _FanSpeedChart extends StatelessWidget {
  const _FanSpeedChart({required this.history});

  final List<SensorRecord> history;

  List<FlSpot> _spots(int? Function(SensorRecord) pick) => history
      .asMap()
      .entries
      .where((e) => pick(e.value) != null)
      .map((e) => FlSpot(e.key.toDouble(), pick(e.value)!.toDouble()))
      .toList();

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: _spots((r) => r.fan1Rpm),
            isCurved: true,
            color: Colors.green,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: _spots((r) => r.fan2Rpm),
            isCurved: true,
            color: Colors.purple,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
      ),
    );
  }
}
