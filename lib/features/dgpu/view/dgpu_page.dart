import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/dgpu_bloc.dart';
import '../bloc/dgpu_event.dart';
import '../models/dgpu_process.dart';
import '../providers/dgpu_provider.dart';

class DgpuPage extends ConsumerWidget {
  const DgpuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dgpuBlocProvider);
    final bloc = ref.read(dgpuBlocProvider.bloc);

    if (state.isLoading && !state.isAvailable) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    return AppPageBody(
      title: 'Discrete GPU',
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        AppSectionCard(
          title: 'Status',
          children: [
            AppRefreshButton(
              isBusy: state.isLoading,
              onPressed: () => bloc.add(const DgpuRefreshRequested()),
            ),
            if (!state.isAvailable)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('NVIDIA GPU not detected'),
                subtitle: Text(
                  'This feature requires a Lenovo Legion with NVIDIA discrete '
                  'graphics in hybrid mode.',
                ),
              )
            else ...[
              _StatusRow(isActive: state.isActive!),
              if (state.pciAddress != null) ...[
                const SizedBox(height: 4),
                Text(
                  'PCI address: ${state.pciAddress}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
        if (state.isAvailable) ...[
          const SizedBox(height: 16),
          AppSectionCard(
            title: 'Compute Processes',
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
            ],
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            title: 'Deactivation',
            children: [
              Text(
                'Kill GPU processes before restarting the PCI device. '
                'Restarting the PCI device will briefly remove the GPU from '
                'the system. Save any work before proceeding.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              const PrivilegedActionNotice(),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: state.isApplying
                        ? null
                        : () => _killProcesses(context, bloc),
                    icon: state.isApplying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: YaruCircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.close_outlined, size: 16),
                    label: const Text('Kill GPU Processes'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.isApplying
                        ? null
                        : () => _restartPci(context, bloc),
                    icon: const Icon(Icons.refresh_outlined, size: 16),
                    label: const Text('Restart PCI Device'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
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

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isActive ? Icons.memory : Icons.power_settings_new_outlined,
          size: 18,
          color: isActive
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 8),
        Text(
          isActive ? 'GPU active' : 'GPU suspended (D3cold)',
          style: Theme.of(context).textTheme.bodyMedium,
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
