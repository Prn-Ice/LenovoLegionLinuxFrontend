import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../../power/bloc/power_event.dart';
import '../../power/providers/power_provider.dart';
import '../../sensors/bloc/live_sensor_event.dart';
import '../../sensors/providers/live_sensor_provider.dart';
import '../bloc/dgpu_bloc.dart';
import '../bloc/dgpu_event.dart';
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dgpuBlocProvider);
    final sensorState = ref.watch(liveSensorBlocProvider);
    final powerState = ref.watch(powerBlocProvider);
    final bloc = ref.read(dgpuBlocProvider.bloc);

    if (state.isLoading && !state.isAvailable) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    return AppPageBody(
      title: 'Discrete GPU',
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        if (!state.isAvailable)
          AppControlCard(
            icon: Icons.memory,
            title: 'GPU',
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('NVIDIA GPU not detected'),
                subtitle: Text(
                  'This feature requires a Lenovo Legion with NVIDIA discrete '
                  'graphics in hybrid mode.',
                ),
              ),
            ],
          )
        else ...[
          // ── Stats ────────────────────────────────────────────────────────
          AppControlCard(
            icon: Icons.memory,
            title: 'Stats',
            trailing: AppRefreshButton(
              isBusy: state.isLoading,
              onPressed: () => bloc.add(const DgpuRefreshRequested()),
            ),
            children: [
              if (state.pciAddress != null) ...[
                _infoRow(context, 'PCI address', state.pciAddress!),
                _infoRow(
                  context,
                  'Runtime',
                  state.isActive == true ? 'Active' : 'Suspended (D3cold)',
                ),
                const SizedBox(height: 4),
              ],
              if (!sensorState.snapshot.gpuIsDiscrete)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('GPU stats'),
                  subtitle: Text(
                    'Discrete GPU is not active — using integrated graphics',
                  ),
                )
              else ...[
                _infoRow(
                  context,
                  'Name',
                  sensorState.snapshot.gpuName ?? '—',
                ),
                _infoRow(
                  context,
                  'Utilisation',
                  sensorState.snapshot.gpuUtilPercent != null
                      ? '${sensorState.snapshot.gpuUtilPercent!.toStringAsFixed(0)}%'
                      : '—',
                ),
                _infoRow(
                  context,
                  'Clock',
                  sensorState.snapshot.gpuClockGhz != null
                      ? '${sensorState.snapshot.gpuClockGhz!.toStringAsFixed(2)} GHz'
                      : '—',
                ),
                _infoRow(
                  context,
                  'Temperature',
                  sensorState.snapshot.gpuTempC != null
                      ? '${sensorState.snapshot.gpuTempC!.toStringAsFixed(1)} °C'
                      : '—',
                ),
                _infoRow(
                  context,
                  'Fan',
                  sensorState.snapshot.gpuFanRpm != null
                      ? '${sensorState.snapshot.gpuFanRpm!.round()} RPM'
                      : '—',
                ),
                _infoRow(
                  context,
                  'VRAM used',
                  sensorState.snapshot.gpuVramUsedGb != null
                      ? '${sensorState.snapshot.gpuVramUsedGb!.toStringAsFixed(1)} / '
                            '${sensorState.snapshot.gpuVramTotalGb?.toStringAsFixed(1) ?? '?'} GiB'
                      : '—',
                ),
                _infoRow(
                  context,
                  'Power',
                  sensorState.snapshot.gpuPowerDrawW != null
                      ? '${sensorState.snapshot.gpuPowerDrawW!.toStringAsFixed(1)} W'
                      : '—',
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // ── Processes ────────────────────────────────────────────────────
          AppControlCard(
            icon: Icons.list_alt_outlined,
            title: 'Processes',
            children: [
              if (state.processes.isEmpty)
                Text(
                  'No compute processes on GPU.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                )
              else
                _ProcessTable(processes: state.processes),
              const SizedBox(height: 4),
              Text(
                'Shows CUDA/compute processes only. Display server processes '
                '(Xorg, Wayland compositor) may not appear here.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              const PrivilegedActionNotice(),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: state.isApplying
                    ? null
                    : () => _killProcesses(context, bloc),
                icon: state.isApplying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: YaruCircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.close_outlined, size: 16),
                label: const Text('Kill GPU Processes'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── PCI ──────────────────────────────────────────────────────────
          AppControlCard(
            icon: Icons.developer_board_outlined,
            title: 'PCI',
            description:
                'Kill GPU processes before restarting the PCI device. '
                'Restarting the PCI device will briefly remove the GPU from '
                'the system. Save any work before proceeding.',
            children: [
              const PrivilegedActionNotice(),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: state.isApplying
                    ? null
                    : () => _restartPci(context, bloc),
                icon: const Icon(Icons.refresh_outlined, size: 16),
                label: const Text('Restart PCI Device'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Performance ──────────────────────────────────────────────────
          AppControlCard(
            icon: Icons.speed_outlined,
            title: 'Performance',
            children: [
              const PrivilegedActionNotice(),
              const SizedBox(height: 8),
              AppSwitchTile(
                value: powerState.gpuOverclockEnabled ?? false,
                onChanged: (powerState.gpuOverclockEnabled != null &&
                        !powerState.isApplying)
                    ? (enabled) async {
                        final confirmed = await confirmPrivilegedAction(
                          context,
                          title: 'Toggle GPU overclock',
                          message:
                              'This action uses privileged access and may require authentication.',
                          confirmLabel: 'Apply',
                        );
                        if (!context.mounted || !confirmed) return;
                        ref
                            .read(powerBlocProvider.bloc)
                            .add(GpuOverclockSetRequested(enabled));
                      }
                    : null,
                title: 'GPU overclock',
                subtitle: powerState.gpuOverclockEnabled == null
                    ? 'Not supported on this device'
                    : boolEnabledLabel(powerState.gpuOverclockEnabled),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Hybrid Mode ──────────────────────────────────────────────────
          AppControlCard(
            icon: Icons.device_hub_outlined,
            title: 'Hybrid Mode',
            description: 'Changes take full effect after reboot.',
            children: [
              const PrivilegedActionNotice(),
              const SizedBox(height: 8),
              AppSwitchTile(
                value: state.hybridModeEnabled ?? false,
                onChanged:
                    (state.hybridModeSupported && !state.isApplying)
                        ? (enabled) async {
                            final confirmed = await confirmPrivilegedAction(
                              context,
                              title: 'Toggle hybrid mode',
                              message:
                                  'This action uses privileged access and may require authentication.',
                              confirmLabel: 'Apply',
                            );
                            if (!context.mounted || !confirmed) return;
                            bloc.add(HybridModeSetRequested(enabled));
                          }
                        : null,
                title: 'Hybrid mode',
                subtitle: state.hybridModeSupported
                    ? boolEnabledLabel(state.hybridModeEnabled)
                    : 'Not supported on this device',
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Future<void> _killProcesses(BuildContext context, DgpuBloc bloc) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Kill GPU Processes',
      message:
          'This will send SIGKILL to all compute processes using the GPU. '
          'Applications may lose unsaved work. Continue?',
      confirmLabel: 'Kill processes',
    );
    if (confirmed && context.mounted) {
      bloc.add(const DgpuKillProcessesRequested());
    }
  }

  Future<void> _restartPci(BuildContext context, DgpuBloc bloc) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Restart PCI Device',
      message:
          'This will remove the GPU from the PCI tree and rescan to '
          'reinitialise it. The GPU will briefly disappear from the system. '
          'Kill GPU processes first. Continue?',
      confirmLabel: 'Restart device',
    );
    if (confirmed && context.mounted) {
      bloc.add(const DgpuRestartPciRequested());
    }
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
        dataRowMinHeight: 32,
        dataRowMaxHeight: 36,
        columns: const [
          DataColumn(label: Text('PID')),
          DataColumn(label: Text('Process')),
          DataColumn(label: Text('GPU Mem'), numeric: true),
        ],
        rows: [
          for (final p in processes)
            DataRow(cells: [
              DataCell(Text('${p.pid}')),
              DataCell(Text(p.name)),
              DataCell(Text('${p.usedMemoryMib} MiB')),
            ]),
        ],
      ),
    );
  }
}
