import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/models/bridge_command_record.dart';
import '../../../core/widgets/app_shell_components.dart';
import '../../about/bloc/about_event.dart';
import '../../about/models/about_diagnostic_item.dart';
import '../../about/models/about_snapshot.dart';
import '../../about/providers/about_provider.dart';
import '../../analytics/bloc/analytics_event.dart';
import '../../analytics/bloc/analytics_state.dart';
import '../../analytics/models/sensor_record.dart';
import '../../analytics/providers/analytics_provider.dart';

class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  @override
  void initState() {
    super.initState();
    // aboutBlocProvider auto-dispatches AboutStarted in its provider constructor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(analyticsBlocProvider.bloc).add(const AnalyticsStarted());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final analyticsState = ref.watch(analyticsBlocProvider);
    final aboutState = ref.watch(aboutBlocProvider);
    final snapshot = aboutState.snapshot;

    return AppPageBody(
      title: 'Diagnostics',
      errorMessage: aboutState.errorMessage ?? analyticsState.errorMessage,
      children: [
        // ── Live Sensors ─────────────────────────────────────────────────────
        AppControlCard(
          icon: Icons.analytics_outlined,
          title: 'Live Sensors',
          description: 'Temperature and fan speed history.',
          children: [
            _SensorReadings(latest: analyticsState.latest),
            const SizedBox(height: 12),
            YaruChoiceChipBar(
              selectedFirst: false,
              labels: AnalyticsTimeWindow.values
                  .map((w) => Text(w.label))
                  .toList(),
              isSelected: AnalyticsTimeWindow.values
                  .map((w) => w == analyticsState.window)
                  .toList(),
              onSelected: (i) => ref
                  .read(analyticsBlocProvider.bloc)
                  .add(AnalyticsWindowChanged(AnalyticsTimeWindow.values[i])),
            ),
            const SizedBox(height: 12),
            if (analyticsState.history.length > 1) ...[
              _ChartSection(
                title: 'Temperature (°C)',
                child: _TemperatureChart(history: analyticsState.history),
              ),
              const SizedBox(height: 16),
              _ChartSection(
                title: 'Fan Speed (RPM)',
                child: _FanSpeedChart(history: analyticsState.history),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('Collecting sensor data…')),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Environment ──────────────────────────────────────────────────────
        AppControlCard(
          icon: Icons.computer_outlined,
          title: 'Environment',
          children: [
            if (aboutState.isLoading && snapshot == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: YaruCircularProgressIndicator(),
                ),
              )
            else ...[
              _StatusLine(
                label: 'Hardware',
                value: snapshot?.hardwareModel ?? 'Unknown',
                status: snapshot?.hardwareModel != null
                    ? AboutDiagnosticStatus.ok
                    : AboutDiagnosticStatus.unavailable,
              ),
              _StatusLine(
                label: 'Kernel',
                value: snapshot?.kernelVersion ?? 'Unknown',
                status: snapshot?.kernelVersion != null
                    ? AboutDiagnosticStatus.ok
                    : AboutDiagnosticStatus.unavailable,
              ),
              _StatusLine(
                label: 'Module version',
                value: snapshot?.moduleVersion ?? 'Unknown',
                status: snapshot?.moduleVersion != null
                    ? AboutDiagnosticStatus.ok
                    : AboutDiagnosticStatus.unavailable,
              ),
              _StatusLine(
                label: 'CLI version',
                value: snapshot?.cliVersion ?? 'Unknown',
                status: snapshot?.cliVersion != null
                    ? AboutDiagnosticStatus.ok
                    : AboutDiagnosticStatus.unavailable,
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // ── Runtime Dependencies ─────────────────────────────────────────────
        AppControlCard(
          icon: Icons.link_outlined,
          title: 'Runtime Dependencies',
          children: [
            if (snapshot == null && !aboutState.isLoading)
              const Text('No diagnostics available.')
            else ...[
              _StatusLine(
                label: 'CLI path',
                value: snapshot?.cliPath ?? 'Unknown',
                status: snapshot == null
                    ? AboutDiagnosticStatus.unavailable
                    : snapshot.cliPathExists
                    ? AboutDiagnosticStatus.ok
                    : AboutDiagnosticStatus.error,
                details: snapshot != null && !snapshot.cliPathExists
                    ? 'CLI script was not found at this location.'
                    : null,
              ),
              _StatusLine(
                label: 'python3',
                value: _boolLabel(snapshot?.pythonAvailable),
                status: _boolStatus(snapshot?.pythonAvailable),
              ),
              _StatusLine(
                label: 'pkexec',
                value: _boolLabel(snapshot?.pkexecAvailable),
                status: _boolStatus(snapshot?.pkexecAvailable),
              ),
              _StatusLine(
                label: 'systemctl',
                value: _boolLabel(snapshot?.systemctlAvailable),
                status: _boolStatus(snapshot?.systemctlAvailable),
              ),
              _StatusLine(
                label: 'CLI health',
                value: snapshot?.cliHealthSummary ?? 'Unknown',
                status: snapshot == null
                    ? AboutDiagnosticStatus.unavailable
                    : snapshot.cliHealthy
                    ? AboutDiagnosticStatus.ok
                    : AboutDiagnosticStatus.error,
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // ── Capability Probes ────────────────────────────────────────────────
        if (snapshot != null && snapshot.diagnostics.isNotEmpty) ...[
          AppControlCard(
            icon: Icons.checklist_outlined,
            title: 'Backend Capability Probes',
            children: snapshot.diagnostics
                .map(
                  (item) => _StatusLine(
                    label: item.label,
                    value: item.value,
                    status: item.status,
                    details: item.details,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
        ],

        // ── Command History ──────────────────────────────────────────────────
        AppControlCard(
          icon: Icons.history_outlined,
          title: 'Command History (last 20)',
          trailing: snapshot != null
              ? OutlinedButton.icon(
                  onPressed: () => _copyDiagnosticsJson(context, snapshot),
                  icon: const Icon(Icons.copy_all_outlined, size: 16),
                  label: const Text('Copy JSON'),
                )
              : null,
          children: [
            if (snapshot == null || snapshot.commandHistory.isEmpty)
              const Text('No commands recorded yet.')
            else
              ...snapshot.commandHistory.reversed.map(
                (record) => _CommandHistoryTile(record: record),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Actions ──────────────────────────────────────────────────────────
        Row(
          children: [
            AppRefreshButton(
              isBusy: aboutState.isLoading,
              onPressed: () => ref
                  .read(aboutBlocProvider.bloc)
                  .add(const AboutRefreshRequested()),
              label: 'Refresh diagnostics',
            ),
          ],
        ),
      ],
    );
  }

  static String _boolLabel(bool? value) {
    if (value == null) return 'Unknown';
    return value ? 'Available' : 'Missing';
  }

  static AboutDiagnosticStatus _boolStatus(bool? value) {
    if (value == null) return AboutDiagnosticStatus.unavailable;
    return value ? AboutDiagnosticStatus.ok : AboutDiagnosticStatus.error;
  }

  Future<void> _copyDiagnosticsJson(
    BuildContext context,
    AboutSnapshot snapshot,
  ) async {
    final payload = <String, Object?>{
      'updated_at': snapshot.updatedAt.toIso8601String(),
      'cli_path': snapshot.cliPath,
      'cli_path_exists': snapshot.cliPathExists,
      'python_available': snapshot.pythonAvailable,
      'pkexec_available': snapshot.pkexecAvailable,
      'systemctl_available': snapshot.systemctlAvailable,
      'cli_healthy': snapshot.cliHealthy,
      'cli_health_summary': snapshot.cliHealthSummary,
      'kernel_version': snapshot.kernelVersion,
      'hardware_model': snapshot.hardwareModel,
      'module_version': snapshot.moduleVersion,
      'cli_version': snapshot.cliVersion,
      'diagnostics': snapshot.diagnostics
          .map(
            (e) => <String, Object?>{
              'id': e.id,
              'label': e.label,
              'status': e.status.name,
              'value': e.value,
              'details': e.details,
            },
          )
          .toList(growable: false),
      'command_history': snapshot.commandHistory
          .map(
            (r) => <String, Object?>{
              'timestamp': r.timestamp.toIso8601String(),
              'method': r.method,
              'args': r.redactedArgs,
              'is_privileged': r.isPrivileged,
              'succeeded': r.succeeded,
              'duration_ms': r.durationMs,
            },
          )
          .toList(growable: false),
    };
    final text = const JsonEncoder.withIndent('  ').convert(payload);
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diagnostics JSON copied to clipboard.')),
      );
    }
  }
}

// ── Sensor reading row ─────────────────────────────────────────────────────

class _SensorReadings extends StatelessWidget {
  const _SensorReadings({required this.latest});

  final SensorRecord? latest;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ReadingChip(
            icon: Icons.thermostat_outlined,
            label: 'CPU',
            value: latest?.cpuTempC != null
                ? '${latest!.cpuTempC!.toStringAsFixed(1)} °C'
                : '—',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ReadingChip(
            icon: Icons.thermostat_outlined,
            label: 'GPU',
            value: latest?.gpuTempC != null
                ? '${latest!.gpuTempC!.toStringAsFixed(1)} °C'
                : '—',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ReadingChip(
            icon: Icons.air_outlined,
            label: 'Fan 1',
            value: latest?.fan1Rpm != null ? '${latest!.fan1Rpm} RPM' : '—',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ReadingChip(
            icon: Icons.air_outlined,
            label: 'Fan 2',
            value: latest?.fan2Rpm != null ? '${latest!.fan2Rpm} RPM' : '—',
          ),
        ),
      ],
    );
  }
}

class _ReadingChip extends StatelessWidget {
  const _ReadingChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: scheme.outline),
              const SizedBox(width: 4),
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(color: scheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(value, style: textTheme.titleSmall),
        ],
      ),
    );
  }
}

// ── Chart sections ─────────────────────────────────────────────────────────

class _ChartSection extends StatelessWidget {
  const _ChartSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        YaruBorderContainer(child: SizedBox(height: 140, child: child)),
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
    final scheme = Theme.of(context).colorScheme;
    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: _spots((r) => r.cpuTempC),
            isCurved: true,
            color: scheme.error,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: _spots((r) => r.gpuTempC),
            isCurved: true,
            color: scheme.primary,
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
    final scheme = Theme.of(context).colorScheme;
    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: _spots((r) => r.fan1Rpm),
            isCurved: true,
            color: scheme.tertiary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: _spots((r) => r.fan2Rpm),
            isCurved: true,
            color: scheme.secondary,
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

// ── Diagnostics status row ─────────────────────────────────────────────────

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.value,
    required this.status,
    this.details,
  });

  final String label;
  final String value;
  final AboutDiagnosticStatus status;
  final String? details;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);
    return YaruListTile(
      leading: Icon(_statusIcon(status), color: color, size: 20),
      title: Text(label),
      subtitle: details == null ? null : Text(details!),
      trailing: Text(value, style: TextStyle(color: color)),
    );
  }

  Color _statusColor(BuildContext context, AboutDiagnosticStatus status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      AboutDiagnosticStatus.ok => Colors.green.shade700,
      AboutDiagnosticStatus.warning => scheme.tertiary,
      AboutDiagnosticStatus.unavailable => scheme.outline,
      AboutDiagnosticStatus.error => scheme.error,
    };
  }

  IconData _statusIcon(AboutDiagnosticStatus status) {
    return switch (status) {
      AboutDiagnosticStatus.ok => Icons.check_circle_outline,
      AboutDiagnosticStatus.warning => Icons.warning_amber_outlined,
      AboutDiagnosticStatus.unavailable => Icons.help_outline,
      AboutDiagnosticStatus.error => Icons.error_outline,
    };
  }
}

// ── Command history tile ───────────────────────────────────────────────────

class _CommandHistoryTile extends StatelessWidget {
  const _CommandHistoryTile({required this.record});

  final BridgeCommandRecord record;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = record.succeeded ? Colors.green.shade700 : scheme.error;
    final ts = record.timestamp.toLocal();
    final timeLabel =
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';

    return YaruListTile(
      leading: Icon(
        record.succeeded ? Icons.check_circle_outline : Icons.error_outline,
        color: color,
        size: 18,
      ),
      title: Text(
        '${record.method}  ${record.redactedArgs.join(' ')}',
        style: const TextStyle(fontSize: 12),
      ),
      subtitle: Text(
        timeLabel,
        style: TextStyle(fontSize: 11, color: scheme.outline),
      ),
      trailing: Text(
        '${record.durationMs} ms',
        style: TextStyle(fontSize: 11, color: scheme.outline),
      ),
    );
  }
}
