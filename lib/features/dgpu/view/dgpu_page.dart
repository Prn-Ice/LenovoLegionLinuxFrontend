import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/metric_text.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../../../core/widgets/surface_card.dart';
import '../../analytics/bloc/analytics_event.dart';
import '../../analytics/models/sensor_record.dart';
import '../../analytics/providers/analytics_provider.dart';
import '../../analytics/view/widgets/telemetry_history_card.dart';
import '../../power/bloc/power_event.dart';
import '../../power/providers/power_provider.dart';
import '../../sensors/bloc/live_sensor_event.dart';
import '../../sensors/models/live_sensor_snapshot.dart';
import '../../sensors/providers/live_sensor_provider.dart';
import '../bloc/dgpu_bloc.dart';
import '../bloc/dgpu_event.dart';
import '../bloc/dgpu_state.dart';
import '../models/dgpu_process.dart';
import '../providers/dgpu_provider.dart';

class DgpuPage extends ConsumerStatefulWidget {
  const DgpuPage({super.key});

  @override
  ConsumerState<DgpuPage> createState() => _DgpuPageState();
}

class _DgpuPageState extends ConsumerState<DgpuPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveSensorBlocProvider.bloc).add(const LiveSensorStarted());
      ref.read(analyticsBlocProvider.bloc).add(const AnalyticsStarted());
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dgpuBlocProvider);
    final sensorState = ref.watch(liveSensorBlocProvider);
    final analytics = ref.watch(analyticsBlocProvider);
    final powerState = ref.watch(powerBlocProvider);
    final bloc = ref.read(dgpuBlocProvider.bloc);
    final analyticsBloc = ref.read(analyticsBlocProvider.bloc);

    if (state.isLoading && !state.isAvailable) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    return AppPageBody(
      title: 'Discrete GPU',
      errorMessage: state.errorMessage ?? analytics.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        if (!state.isAvailable)
          AppControlCard(
            icon: Icons.memory,
            title: 'GPU unavailable',
            children: [
              const Text(
                'No NVIDIA display controller with runtime power management '
                'was found. Hybrid mode and NVIDIA drivers are required.',
              ),
              const SizedBox(height: 12),
              AppRefreshButton(
                isBusy: state.isLoading,
                onPressed: () => bloc.add(const DgpuRefreshRequested()),
              ),
            ],
          )
        else ...[
          _GpuOverview(
            state: state,
            sensor: sensorState.snapshot,
            onRefresh: state.isApplying
                ? null
                : () => bloc.add(const DgpuRefreshRequested()),
          ),
          const SizedBox(height: 16),
          TelemetryHistoryCard(
            history: analytics.history,
            window: analytics.window,
            isCollecting: analytics.isCollecting,
            accentColor: const Color(0xff2F9BFF),
            onWindowChanged: analyticsBloc.add,
            options: const [
              TelemetrySeriesOption(
                label: 'Usage %',
                unit: '%',
                minimumY: 0,
                maximumY: 100,
                valueOf: _gpuUtilisation,
              ),
              TelemetrySeriesOption(
                label: 'Temperature',
                unit: '°C',
                valueOf: _gpuTemperature,
              ),
              TelemetrySeriesOption(
                label: 'Power draw',
                unit: 'W',
                minimumY: 0,
                valueOf: _gpuPower,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ProcessesCard(processes: state.processes),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 780
                  ? (constraints.maxWidth - 14) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: width,
                    child: _WorkingModeCard(
                      state: state,
                      isOverclockEnabled: powerState.gpuOverclockEnabled,
                      isPowerApplying: powerState.isApplying,
                      onOverclockChanged: (enabled) =>
                          _setOverclock(context, enabled),
                      onHybridChanged: (enabled) =>
                          _setHybridMode(context, bloc, state, enabled),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _DeactivateCard(
                      state: state,
                      onKill: () => _killProcesses(context, bloc, state),
                      onRestart: () => _restartPci(context, bloc, state),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Future<void> _setOverclock(BuildContext context, bool enabled) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: '${enabled ? 'Enable' : 'Disable'} GPU overclock',
      message:
          'This changes the GPU overclock setting with privileged access. '
          'Apply this change?',
      confirmLabel: 'Apply',
    );
    if (!context.mounted || !confirmed) return;
    ref.read(powerBlocProvider.bloc).add(GpuOverclockSetRequested(enabled));
  }

  Future<void> _setHybridMode(
    BuildContext context,
    DgpuBloc bloc,
    DgpuState state,
    bool enabled,
  ) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: '${enabled ? 'Enable' : 'Disable'} hybrid mode',
      message:
          'This changes the working graphics mode and requires a reboot. '
          'Apply the change to ${enabled ? 'hybrid graphics' : 'discrete graphics only'}?',
      confirmLabel: 'Apply',
    );
    if (!context.mounted || !confirmed) return;
    bloc.add(HybridModeSetRequested(enabled));
  }

  Future<void> _killProcesses(
    BuildContext context,
    DgpuBloc bloc,
    DgpuState state,
  ) async {
    if (state.processes.isEmpty) return;
    final pids = state.processes.map((process) => process.pid).join(', ');
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Kill ${state.processes.length} GPU processes',
      message:
          'This sends SIGKILL to the confirmed compute process targets '
          '(PIDs $pids). Applications may lose unsaved work. Continue?',
      confirmLabel: 'Kill processes',
    );
    if (confirmed && context.mounted) {
      bloc.add(
        DgpuKillProcessesRequested(
          state.processes.map((process) => process.pid).toList(),
        ),
      );
    }
  }

  Future<void> _restartPci(
    BuildContext context,
    DgpuBloc bloc,
    DgpuState state,
  ) async {
    final address = state.pciAddress;
    if (address == null) return;
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Restart GPU PCI device',
      message:
          'This removes $address from the PCI tree and rescans it. The GPU '
          'will briefly disappear. Close GPU applications first. Continue?',
      confirmLabel: 'Restart device',
    );
    if (confirmed && context.mounted) {
      bloc.add(DgpuRestartPciRequested(address));
    }
  }
}

class _GpuOverview extends StatelessWidget {
  const _GpuOverview({
    required this.state,
    required this.sensor,
    required this.onRefresh,
  });

  final DgpuState state;
  final LiveSensorSnapshot sensor;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final telemetryAvailable = sensor.gpuIsDiscrete;
    final name = telemetryAvailable && sensor.gpuName != null
        ? sensor.gpuName!
        : state.name ?? 'NVIDIA discrete GPU';
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xff2F9BFF).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(11),
                  child: Icon(Icons.memory, size: 20, color: Color(0xff2F9BFF)),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${state.pciAddress ?? 'PCI address unavailable'} · '
                      '${state.hybridModeEnabled == true
                          ? 'Hybrid mode on'
                          : state.hybridModeEnabled == false
                          ? 'Discrete mode'
                          : 'Working mode unknown'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _RuntimeBadge(isActive: state.isActive),
              IconButton(
                tooltip: 'Refresh GPU status',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 26,
            runSpacing: 14,
            children: [
              _GpuMetric(
                value: telemetryAvailable
                    ? sensor.gpuPerformanceState ?? '—'
                    : '—',
                label: 'Power state',
              ),
              _GpuMetric(
                value: telemetryAvailable
                    ? _measurement(sensor.gpuTempC, '°', 0)
                    : '—',
                label: 'Temperature',
              ),
              _GpuMetric(
                value: telemetryAvailable
                    ? _measurement(sensor.gpuPowerDrawW, 'W', 1)
                    : '—',
                label: 'Power draw',
              ),
              _GpuMetric(
                value: telemetryAvailable
                    ? _vramLabel(sensor.gpuVramUsedGb, sensor.gpuVramTotalGb)
                    : '—',
                label: 'VRAM',
              ),
              _GpuMetric(
                value: telemetryAvailable
                    ? _measurement(sensor.gpuUtilPercent, '%', 0)
                    : '—',
                label: 'Usage',
              ),
            ],
          ),
          if (!telemetryAvailable) ...[
            const SizedBox(height: 14),
            Text(
              state.isActive == false
                  ? 'Live NVIDIA telemetry is unavailable while the GPU is suspended.'
                  : 'Live NVIDIA telemetry is unavailable. Check the NVIDIA driver and nvidia-smi.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _RuntimeBadge extends StatelessWidget {
  const _RuntimeBadge({required this.isActive});

  final bool? isActive;

  @override
  Widget build(BuildContext context) {
    final active = isActive == true;
    final color = active
        ? const Color(0xff3FBF6F)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              isActive == null
                  ? 'Unknown'
                  : active
                  ? 'Active'
                  : 'Suspended',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _GpuMetric extends StatelessWidget {
  const _GpuMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: monoGaugeStyle(82, scheme.onSurface).copyWith(fontSize: 20),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ProcessesCard extends StatelessWidget {
  const _ProcessesCard({required this.processes});

  final List<DgpuProcess> processes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                'Processes',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '${processes.length} compute ${processes.length == 1 ? 'process' : 'processes'}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (processes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No CUDA compute processes are using the GPU.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          else
            _ProcessTable(processes: processes),
          const SizedBox(height: 8),
          Text(
            'Display server processes may not appear in this list.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _WorkingModeCard extends StatelessWidget {
  const _WorkingModeCard({
    required this.state,
    required this.isOverclockEnabled,
    required this.isPowerApplying,
    required this.onOverclockChanged,
    required this.onHybridChanged,
  });

  final DgpuState state;
  final bool? isOverclockEnabled;
  final bool isPowerApplying;
  final ValueChanged<bool> onOverclockChanged;
  final ValueChanged<bool> onHybridChanged;

  @override
  Widget build(BuildContext context) {
    return AppControlCard(
      icon: Icons.tune,
      title: 'Working mode',
      description: 'Graphics mode changes take full effect after a reboot.',
      children: [
        const PrivilegedActionNotice(),
        const SizedBox(height: 8),
        AppSwitchTile(
          value: state.hybridModeEnabled ?? false,
          onChanged: state.hybridModeSupported && !state.isApplying
              ? onHybridChanged
              : null,
          title: 'Hybrid mode',
          subtitle: state.hybridModeSupported
              ? boolEnabledLabel(state.hybridModeEnabled)
              : 'Not supported on this device',
        ),
        AppSwitchTile(
          value: isOverclockEnabled ?? false,
          onChanged: isOverclockEnabled != null && !isPowerApplying
              ? onOverclockChanged
              : null,
          title: 'GPU overclock',
          subtitle: isOverclockEnabled == null
              ? 'Not supported on this device'
              : boolEnabledLabel(isOverclockEnabled),
        ),
      ],
    );
  }
}

class _DeactivateCard extends StatelessWidget {
  const _DeactivateCard({
    required this.state,
    required this.onKill,
    required this.onRestart,
  });

  final DgpuState state;
  final VoidCallback onKill;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppControlCard(
      icon: Icons.power_settings_new,
      title: 'Deactivate & restart',
      description:
          'Stop confirmed compute processes before restarting the GPU PCI device.',
      children: [
        const PrivilegedActionNotice(),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'These actions can terminate applications or temporarily remove '
              'the GPU. Save your work before continuing.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: state.isApplying || state.processes.isEmpty
                  ? null
                  : onKill,
              icon: const Icon(Icons.close, size: 17),
              label: Text(
                state.processes.isEmpty
                    ? 'No process targets'
                    : 'Kill ${state.processes.length} processes',
              ),
            ),
            OutlinedButton.icon(
              onPressed:
                  state.isApplying ||
                      state.pciAddress == null ||
                      state.processes.isNotEmpty
                  ? null
                  : onRestart,
              icon: const Icon(Icons.restart_alt, size: 17),
              label: const Text('Restart PCI device'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProcessTable extends StatelessWidget {
  const _ProcessTable({required this.processes});

  final List<DgpuProcess> processes;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 40,
        columns: const [
          DataColumn(label: Text('PID')),
          DataColumn(label: Text('Process')),
          DataColumn(label: Text('GPU memory'), numeric: true),
        ],
        rows: [
          for (final process in processes)
            DataRow(
              cells: [
                DataCell(Text('${process.pid}')),
                DataCell(Text(process.name)),
                DataCell(Text('${process.usedMemoryMib} MiB')),
              ],
            ),
        ],
      ),
    );
  }
}

double? _gpuUtilisation(SensorRecord record) => record.gpuUtilPercent;
double? _gpuTemperature(SensorRecord record) => record.gpuTempC;
double? _gpuPower(SensorRecord record) => record.gpuPowerDrawW;

String _measurement(double? value, String unit, int precision) =>
    value == null ? '—' : '${value.toStringAsFixed(precision)} $unit';

String _vramLabel(double? used, double? total) {
  if (used == null || total == null) return '—';
  return '${used.toStringAsFixed(1)} / ${total.toStringAsFixed(1)} GB';
}
