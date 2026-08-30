import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yaru/yaru.dart';

import '../../../core/theme/legion_accent.dart';
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
    final accent =
        LegionAccent.fromPowerModeValue(powerState.currentMode?.value)?.color ??
        Theme.of(context).colorScheme.primary;

    if (!state.hasLoaded || (state.isAvailable && sensorState.isLoading)) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    return AppPageBody(
      errorMessage:
          state.errorMessage ??
          sensorState.errorMessage ??
          analytics.errorMessage,
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
          _GpuOverview(state: state, sensor: sensorState.snapshot),
          const SizedBox(height: 16),
          TelemetryHistoryCard(
            history: analytics.history,
            window: analytics.window,
            isCollecting: analytics.isCollecting,
            accentColor: accent,
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
          _GraphicsModeCard(
            state: state,
            accent: accent,
            onModeChanged: (mode) => _setGraphicsMode(context, bloc, mode),
          ),
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
                    child: _DeactivateCard(
                      state: state,
                      onKill: () => _killProcesses(context, bloc, state),
                      onRestart: () => _restartPci(context, bloc, state),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _GpuPerformanceCard(
                      accent: accent,
                      isOverclockEnabled: powerState.gpuOverclockEnabled,
                      isPowerApplying: powerState.isApplying,
                      onOverclockChanged: (enabled) =>
                          _setOverclock(context, enabled),
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

  Future<void> _setGraphicsMode(
    BuildContext context,
    DgpuBloc bloc,
    _GraphicsMode mode,
  ) async {
    if (mode == _GraphicsMode.integratedOnly) return;
    final hybridEnabled = mode == _GraphicsMode.hybrid;
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Configure ${mode.label}',
      message:
          '${mode.confirmation} A reboot is required before the new graphics '
          'mode takes effect.',
      confirmLabel: 'Configure mode',
    );
    if (!context.mounted || !confirmed) return;
    bloc.add(HybridModeSetRequested(hybridEnabled));
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
  const _GpuOverview({required this.state, required this.sensor});

  final DgpuState state;
  final LiveSensorSnapshot sensor;

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
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: _GpuVendorMark(name: name),
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
                      'Discrete GPU · '
                      '${state.hybridModeEnabled == true
                          ? 'Hybrid configured'
                          : state.hybridModeEnabled == false
                          ? 'Discrete-only configured'
                          : 'Graphics mode unknown'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _RuntimeBadge(isActive: state.isActive),
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

class _GpuVendorMark extends StatelessWidget {
  const _GpuVendorMark({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final normalized = name.toLowerCase();
    final vendor = normalized.contains('nvidia')
        ? 'nvidia'
        : normalized.contains('amd') || normalized.contains('radeon')
        ? 'amd'
        : normalized.contains('intel') || normalized.contains('arc')
        ? 'intel'
        : null;

    if (vendor == null) {
      return Icon(
        Icons.memory,
        key: const ValueKey('gpu-vendor-unknown'),
        size: 24,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }

    return SvgPicture.asset(
      'assets/gpu_vendors/$vendor.svg',
      key: ValueKey('gpu-vendor-$vendor'),
      width: 24,
      height: 24,
      semanticsLabel: '${vendor.toUpperCase()} GPU',
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
                'Processes on the dGPU',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '${processes.length} running',
                style: monoFactStyle(
                  scheme,
                ).copyWith(color: scheme.onSurfaceVariant, fontSize: 11),
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
            for (final process in processes) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        process.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'PID ${process.pid}',
                      style: monoFactStyle(
                        scheme,
                      ).copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      _memoryLabel(process.usedMemoryMib),
                      style: monoFactStyle(scheme),
                    ),
                  ],
                ),
              ),
            ],
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

enum _GraphicsMode {
  hybrid(
    label: 'Hybrid',
    description: 'The iGPU handles the desktop; the dGPU wakes when needed.',
    confirmation:
        'Hybrid mode lets the iGPU handle normal work and keeps the dGPU available on demand.',
  ),
  integratedOnly(
    label: 'Integrated only',
    description:
        'Lowest-power mode. Driver support is required; dGPU-wired display ports may be unavailable.',
    confirmation: '',
  ),
  discreteOnly(
    label: 'Discrete only',
    description:
        'The dGPU remains primary for maximum compatibility and performance.',
    confirmation:
        'Discrete-only mode keeps the dGPU as the primary graphics device and increases power use.',
  );

  const _GraphicsMode({
    required this.label,
    required this.description,
    required this.confirmation,
  });

  final String label;
  final String description;
  final String confirmation;
}

class _GraphicsModeCard extends StatelessWidget {
  const _GraphicsModeCard({
    required this.state,
    required this.accent,
    required this.onModeChanged,
  });

  final DgpuState state;
  final Color accent;
  final ValueChanged<_GraphicsMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final configuredMode = state.hybridModeEnabled == null
        ? null
        : state.hybridModeEnabled!
        ? _GraphicsMode.hybrid
        : _GraphicsMode.discreteOnly;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Graphics mode',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                configuredMode == null
                    ? 'Unavailable'
                    : 'Configured: ${configuredMode.label}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: configuredMode == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Choose the graphics configuration for the next boot.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < _GraphicsMode.values.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            _GraphicsModeTile(
              mode: _GraphicsMode.values[index],
              configuredMode: configuredMode,
              accent: accent,
              enabled:
                  _GraphicsMode.values[index] != _GraphicsMode.integratedOnly &&
                  state.hybridModeSupported &&
                  !state.isApplying,
              onChanged: onModeChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _GraphicsModeTile extends StatelessWidget {
  const _GraphicsModeTile({
    required this.mode,
    required this.configuredMode,
    required this.accent,
    required this.enabled,
    required this.onChanged,
  });

  final _GraphicsMode mode;
  final _GraphicsMode? configuredMode;
  final Color accent;
  final bool enabled;
  final ValueChanged<_GraphicsMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final ValueChanged<_GraphicsMode?>? handleChanged = enabled
        ? (value) {
            if (value != null && value != configuredMode) onChanged(value);
          }
        : null;

    return YaruRadioListTile<_GraphicsMode>(
      key: ValueKey('graphics-mode-${mode.name}'),
      value: mode,
      groupValue: configuredMode,
      onChanged: handleChanged,
      control: YaruRadio<_GraphicsMode>(
        key: ValueKey('graphics-mode-${mode.name}-control'),
        value: mode,
        groupValue: configuredMode,
        onChanged: handleChanged,
        selectedColor: accent,
      ),
      title: Text(mode.label),
      subtitle: Text(mode.description),
      secondary: mode == _GraphicsMode.integratedOnly
          ? Text(
              'Unavailable',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      contentPadding: EdgeInsets.zero,
    );
  }
}

class _GpuPerformanceCard extends StatelessWidget {
  const _GpuPerformanceCard({
    required this.accent,
    required this.isOverclockEnabled,
    required this.isPowerApplying,
    required this.onOverclockChanged,
  });

  final Color accent;
  final bool? isOverclockEnabled;
  final bool isPowerApplying;
  final ValueChanged<bool> onOverclockChanged;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'GPU performance',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Optional firmware performance controls.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          _DgpuSwitchRow(
            value: isOverclockEnabled ?? false,
            onChanged: isOverclockEnabled != null && !isPowerApplying
                ? onOverclockChanged
                : null,
            title: 'GPU overclock',
            subtitle: isOverclockEnabled == null
                ? 'Not supported on this device'
                : boolEnabledLabel(isOverclockEnabled),
            accent: accent,
          ),
        ],
      ),
    );
  }
}

class _DgpuSwitchRow extends StatelessWidget {
  const _DgpuSwitchRow({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String title;
  final String subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        YaruSwitch(value: value, selectedColor: accent, onChanged: onChanged),
      ],
    ),
  );
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
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reset discrete GPU',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Close GPU workloads, then restart the PCI device to recover from '
            'a stuck active state.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.admin_panel_settings_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Save your work. Admin authentication is required.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error.withValues(alpha: 0.65)),
                ),
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
          if (state.processes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Restart becomes available after the process list is clear.',
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

double? _gpuUtilisation(SensorRecord record) => record.gpuUtilPercent;
double? _gpuTemperature(SensorRecord record) => record.gpuTempC;
double? _gpuPower(SensorRecord record) => record.gpuPowerDrawW;

String _measurement(double? value, String unit, int precision) =>
    value == null ? '—' : '${value.toStringAsFixed(precision)} $unit';

String _vramLabel(double? used, double? total) {
  if (used == null || total == null) return '—';
  return '${used.toStringAsFixed(1)} / ${total.toStringAsFixed(1)} GB';
}

String _memoryLabel(int memoryMib) => memoryMib >= 1024
    ? '${(memoryMib / 1024).toStringAsFixed(1)} GB'
    : '$memoryMib MiB';
