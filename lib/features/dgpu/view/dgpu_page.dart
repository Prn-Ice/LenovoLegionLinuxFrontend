import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yaru/yaru.dart';

import '../../../core/models/gpu_process.dart';
import '../../../core/models/gpu_process_scan.dart';
import '../../../core/models/gpu_reading.dart';
import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/metric_text.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../../../core/widgets/responsive_card_grid.dart';
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
import '../models/graphics_mode.dart';
import '../providers/dgpu_provider.dart';

const _loadingGpuReadings = 'Loading live GPU readings…';

class DgpuPage extends ConsumerStatefulWidget {
  const DgpuPage({super.key});

  @override
  ConsumerState<DgpuPage> createState() => _DgpuPageState();
}

class _DgpuPageState extends ConsumerState<DgpuPage> {
  _GpuChannel _channel = _GpuChannel.discrete;

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
    final accent = Theme.of(context).colorScheme.primary;

    if (!state.hasLoaded) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    final snapshot = sensorState.snapshot;
    final integratedGpu = snapshot.igpu;
    final integratedProcesses = snapshot.igpuProcesses;
    final discreteProcesses = state.processScan?.processes;
    final availableChannels = <_GpuChannel>[
      if (state.isAvailable) _GpuChannel.discrete,
      if (integratedGpu != null) _GpuChannel.integrated,
    ];
    final channel = availableChannels.contains(_channel)
        ? _channel
        : (availableChannels.isEmpty ? null : availableChannels.first);
    final graphicsModeCard = _GraphicsModeCard(
      state: state,
      isAppImage: Platform.environment['LEGION_APPIMAGE'] == '1',
      onModeSelected: (mode) => _setGraphicsMode(context, bloc, state, mode),
      onBootSupportChanged: (enabled) =>
          _setGraphicsBootSupport(context, bloc, enabled),
    );

    return AppPageBody(
      errorMessage:
          state.errorMessage ??
          sensorState.errorMessage ??
          analytics.errorMessage,
      children: [
        if (availableChannels.length > 1) ...[
          _GpuChannelToolbar(
            channel: channel!,
            channels: availableChannels,
            onChanged: (channel) => setState(() => _channel = channel),
          ),
          const SizedBox(height: 16),
        ],
        if (channel == _GpuChannel.discrete) ...[
          _GpuOverview(
            state: state,
            sensor: snapshot,
            isLoadingReadings: sensorState.isLoading,
          ),
          const SizedBox(height: 16),
          TelemetryHistoryCard(
            key: const ValueKey('gpu-history-discrete'),
            history: analytics.history,
            window: analytics.window,
            isCollecting: analytics.isCollecting,
            accentColor: accent,
            onWindowChanged: analyticsBloc.add,
            options: _discreteHistoryOptions,
          ),
          const SizedBox(height: 16),
          _ProcessesCard(
            key: const ValueKey('gpu-processes-discrete'),
            title: 'Processes with NVIDIA devices open',
            processes: discreteProcesses ?? const [],
            countLabel: discreteProcesses == null
                ? 'Unavailable'
                : '${discreteProcesses.length} found',
            emptyMessage: discreteProcesses == null
                ? 'GPU process list unavailable.'
                : 'No visible processes have NVIDIA devices open.',
            note:
                'The list includes processes this app can inspect. '
                'A process can keep a device open while the GPU sleeps.',
          ),
        ] else if (channel == _GpuChannel.integrated) ...[
          _IntegratedGpuCard(
            gpu: integratedGpu!,
            graphicsModeStatus: state.graphicsModeStatus,
            // This card appears only when the APU supplied a current reading.
            isActive: true,
          ),
          const SizedBox(height: 16),
          TelemetryHistoryCard(
            key: const ValueKey('gpu-history-integrated'),
            history: analytics.history,
            window: analytics.window,
            isCollecting: analytics.isCollecting,
            accentColor: accent,
            onWindowChanged: analyticsBloc.add,
            options: _integratedHistoryOptions,
          ),
          const SizedBox(height: 16),
          _ProcessesCard(
            key: const ValueKey('gpu-processes-integrated'),
            title: 'Processes on the integrated GPU',
            processes: integratedProcesses?.processes ?? const [],
            countLabel: _integratedProcessCount(integratedProcesses),
            emptyMessage: _integratedProcessMessage(integratedProcesses),
            note:
                'Only processes the app can inspect appear. '
                'Display server processes may not appear.',
          ),
        ],
        if (channel == null && sensorState.isLoading)
          const SurfaceCard(
            padding: EdgeInsets.all(16),
            child: Center(child: Text(_loadingGpuReadings)),
          ),
        if (channel != null || sensorState.isLoading)
          const SizedBox(height: 16),
        graphicsModeCard,
        if (channel == _GpuChannel.discrete) ...[
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
                  SizedBox(width: width, child: const _DeactivateCard()),
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
    DgpuState state,
    GraphicsMode mode,
  ) async {
    final bootSupport = state.graphicsModeStatus?.bootSupport;
    final message = switch (mode) {
      GraphicsMode.hybrid =>
        'This makes integrated and NVIDIA graphics available. '
            'Changing which GPU drives the display may require a restart. '
            'Save your work before continuing.',
      GraphicsMode.hybridIgpuOnly when bootSupport != null =>
        'NVIDIA graphics will disconnect when you restart. Displays connected '
            'through NVIDIA may stop working after the restart.',
      GraphicsMode.hybridIgpuOnly =>
        'This can disable NVIDIA graphics while the laptop is running. Disconnect '
            'external displays, save your work, and close GPU-accelerated '
            'applications first.',
      GraphicsMode.discrete =>
        'This selects NVIDIA graphics to drive the display. '
            'You must restart the laptop for the display change to take effect. '
            'Save your work before continuing.',
      GraphicsMode.hybridAuto => '',
    };
    if (mode == GraphicsMode.hybridAuto || state.isApplying) return;
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Switch to ${mode.label}',
      message: message,
      confirmLabel: 'Switch mode',
    );
    if (!context.mounted || !confirmed) return;
    bloc.add(DgpuGraphicsModeSetRequested(mode));
  }

  Future<void> _setGraphicsBootSupport(
    BuildContext context,
    DgpuBloc bloc,
    bool enabled,
  ) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: enabled ? 'Set up iGPU-only at startup' : 'Remove boot support',
      message: enabled
          ? 'Allow Legion to install a startup command that switches to '
                'integrated graphics before sign-in after you select iGPU-only.'
          : 'Remove the startup command installed by the AppImage. '
                'You can return to Hybrid from Graphics mode.',
      confirmLabel: enabled ? 'Set up' : 'Remove',
    );
    if (!context.mounted || !confirmed) return;
    bloc.add(DgpuGraphicsBootSupportSetRequested(enabled));
  }
}

enum _GpuChannel {
  discrete('Discrete GPU'),
  integrated('Integrated GPU');

  const _GpuChannel(this.label);

  final String label;
}

class _GpuChannelToolbar extends StatelessWidget {
  const _GpuChannelToolbar({
    required this.channel,
    required this.channels,
    required this.onChanged,
  });

  final _GpuChannel channel;
  final List<_GpuChannel> channels;
  final ValueChanged<_GpuChannel> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: ToggleButtons(
      key: const ValueKey('gpu-channel-toggle'),
      isSelected: [for (final candidate in channels) candidate == channel],
      onPressed: (index) => onChanged(channels[index]),
      children: [
        for (final candidate in channels)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Text(candidate.label),
          ),
      ],
    ),
  );
}

class _GpuOverview extends StatelessWidget {
  const _GpuOverview({
    required this.state,
    required this.sensor,
    required this.isLoadingReadings,
  });

  final DgpuState state;
  final LiveSensorSnapshot sensor;
  final bool isLoadingReadings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gpu = sensor.dgpu;
    final name = gpu?.name ?? state.name ?? 'NVIDIA discrete GPU';
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
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'GPU · '
                      '${state.graphicsModeStatus?.selectedMode.label ?? 'Graphics mode unavailable'}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
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
              if (gpu?.usagePercent != null)
                _GpuMetric(
                  value: _measurement(gpu!.usagePercent, '%', 0),
                  label: 'Usage',
                ),
              if (gpu?.performanceState != null)
                _GpuMetric(value: gpu!.performanceState!, label: 'Power state'),
              if (gpu?.tempC != null)
                _GpuMetric(
                  value: _measurement(gpu!.tempC, '°', 0),
                  label: 'Temperature',
                ),
              if (gpu?.powerDrawW != null)
                _GpuMetric(
                  value: _measurement(gpu!.powerDrawW, 'W', 1),
                  label: 'Power draw',
                ),
              if (gpu?.vramUsedGb != null && gpu?.vramTotalGb != null)
                _GpuMetric(
                  value: _vramLabel(gpu!.vramUsedGb, gpu.vramTotalGb),
                  label: 'VRAM',
                ),
            ],
          ),
          if (gpu == null) ...[
            const SizedBox(height: 14),
            Text(
              switch ((isLoadingReadings, state.isActive)) {
                (true, _) => _loadingGpuReadings,
                (_, false) => 'Live NVIDIA telemetry is unavailable while the GPU is suspended.',
                _ => 'Live NVIDIA telemetry is unavailable. Run nvidia-smi to check the driver.',
              },
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _IntegratedGpuCard extends StatelessWidget {
  const _IntegratedGpuCard({
    required this.gpu,
    required this.isActive,
    this.graphicsModeStatus,
  });

  final GpuReading gpu;
  final bool isActive;
  final GraphicsModeStatus? graphicsModeStatus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = gpu.name ?? 'Integrated GPU';
    final metrics = [
      if (gpu.usagePercent != null)
        _GpuMetric(
          value: _measurement(gpu.usagePercent, '%', 0),
          label: 'Usage',
        ),
      if (gpu.tempC != null)
        _GpuMetric(
          value: _measurement(gpu.tempC, '°', 0),
          label: 'Temperature',
        ),
      if (gpu.clockGhz != null)
        _GpuMetric(value: _measurement(gpu.clockGhz, 'GHz', 2), label: 'Clock'),
      if (gpu.powerDrawW != null)
        _GpuMetric(
          value: _measurement(gpu.powerDrawW, 'W', 1),
          label: 'Power draw',
        ),
    ];

    return SurfaceCard(
      key: const ValueKey('integrated-gpu-card'),
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
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      graphicsModeStatus == null
                          ? 'Integrated graphics'
                          : 'Integrated graphics · ${graphicsModeStatus!.selectedMode.label}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _RuntimeBadge(isActive: isActive),
            ],
          ),
          if (metrics.isEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Live integrated GPU readings are unavailable. Check the display driver.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ] else ...[
            const SizedBox(height: 18),
            Wrap(spacing: 26, runSpacing: 14, children: metrics),
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
                  : 'Inactive',
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
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ProcessesCard extends StatelessWidget {
  const _ProcessesCard({
    super.key,
    required this.title,
    required this.processes,
    required this.emptyMessage,
    required this.note,
    this.countLabel,
  });

  final String title;
  final List<GpuProcess> processes;
  final String emptyMessage;
  final String note;
  final String? countLabel;

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
                title,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                countLabel ?? '${processes.length} running',
                style: monoFactStyle(scheme)
                    .copyWith(color: scheme.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (processes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  emptyMessage,
                  textAlign: TextAlign.center,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            process.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          if (process.devices.isNotEmpty)
                            Text(
                              process.devices.map(_gpuDeviceLabel).join(', '),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'PID ${process.pid}',
                      style: monoFactStyle(scheme)
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (process.usedMemoryMib case final memory?) ...[
                      const SizedBox(width: 14),
                      Text(_memoryLabel(memory), style: monoFactStyle(scheme)),
                    ],
                  ],
                ),
              ),
            ],
          const SizedBox(height: 8),
          Text(
            note,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _GraphicsModeCard extends StatelessWidget {
  const _GraphicsModeCard({
    required this.state,
    required this.isAppImage,
    required this.onModeSelected,
    required this.onBootSupportChanged,
  });

  final DgpuState state;
  final bool isAppImage;
  final ValueChanged<GraphicsMode> onModeSelected;
  final ValueChanged<bool> onBootSupportChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = state.graphicsModeStatus;
    final bootSupport = status?.bootSupport;

    return SurfaceCard(
      key: const ValueKey('graphics-mode-status'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Graphics mode',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _ReconciliationBadge(status: status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Choose which graphics hardware the laptop can use.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (status == null)
            Text(
              'Graphics status is unavailable. Use Refresh to reload it before changing modes.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = 2;
                final spacing = 16.0;
                final width =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: 14,
                  children: [
                    _GraphicsFact(
                      width: width,
                      label: 'Selected mode',
                      value: status.selectedMode.label,
                    ),
                    _GraphicsFact(
                      width: width,
                      label: 'NVIDIA GPU',
                      value: status.effectiveState.label,
                    ),
                  ],
                );
              },
            ),
            if (status.selectedMode == GraphicsMode.hybridAuto) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(YaruIcons.warning, size: 18, color: scheme.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hybrid Auto is unsafe for desktop use. Unplugging the '
                      'charger can interrupt the display and running applications. '
                      'Keep the charger connected. Save your work, restart the '
                      'laptop, and choose Hybrid/Switchable graphics in BIOS.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            if (status.pendingMode case final pending?) ...[
              const SizedBox(height: 12),
              Text('${pending.label} is scheduled for your next restart.'),
            ] else if (status.reconciliation !=
                GraphicsReconciliation.settled) ...[
              const SizedBox(height: 12),
              Text(
                switch (status.reconciliation) {
                  GraphicsReconciliation.needed => 'Save your work and restart the laptop before changing graphics modes again.',
                  GraphicsReconciliation.blocked =>
                    'Close applications using NVIDIA graphics and disconnect external displays, then try again. '
                        'If the desktop is using NVIDIA graphics, log out and switch modes from a text console.',
                  _ => 'Use Refresh to reload graphics status before changing modes.',
                },
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.warning),
              ),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (bootSupport != null &&
                status.availableModes.contains(
                  GraphicsMode.hybridIgpuOnly,
                )) ...[
              if (!bootSupport.enabled)
                Text(switch (bootSupport.setupUnavailable) {
                  GraphicsBootSetupUnavailable.unsupportedModel =>
                    'iGPU-only startup switching is unavailable on this model.',
                  GraphicsBootSetupUnavailable.missingSystemd =>
                    'iGPU-only startup switching requires systemd.',
                  GraphicsBootSetupUnavailable.missingLsof =>
                    'Install lsof system-wide to set up iGPU-only at startup.',
                  null => 'Set up startup support to use iGPU-only.',
                }),
              if (bootSupport.appImageEnabled ||
                  (isAppImage && bootSupport.setupUnavailable == null))
                TextButton(
                  onPressed: state.isApplying
                      ? null
                      : () =>
                            onBootSupportChanged(!bootSupport.appImageEnabled),
                  child: Text(
                    bootSupport.appImageEnabled
                        ? 'Remove boot support'
                        : 'Set up iGPU-only at startup',
                  ),
                ),
            ],
            Text(
              'Change graphics mode',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            ResponsiveCardGrid(
              minCardWidth: 280,
              children: [
                for (final mode in const [
                  GraphicsMode.hybrid,
                  GraphicsMode.hybridIgpuOnly,
                  GraphicsMode.discrete,
                ])
                  if (status.availableModes.contains(mode))
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OutlinedButton.icon(
                          key: ValueKey('set-graphics-${mode.wireValue}'),
                          onPressed:
                              state.isApplying ||
                                  mode == status.pendingMode ||
                                  (mode == GraphicsMode.hybridIgpuOnly &&
                                      bootSupport?.enabled == false) ||
                                  (mode == status.selectedMode &&
                                      status.pendingMode == null &&
                                      status.reconciliation ==
                                          GraphicsReconciliation.settled)
                              ? null
                              : () => onModeSelected(mode),
                          icon: Icon(
                            mode == status.selectedMode
                                ? YaruIcons.ok
                                : YaruIcons.chip,
                            size: 17,
                          ),
                          label: Text(mode.label),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          mode.description,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
              ],
            ),
            if (state.applyingGraphicsMode != null) ...[
              const SizedBox(height: 10),
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Expanded(child: Text('Switching graphics mode…')),
                ],
              ),
            ],
            const SizedBox(height: 16),
            YaruExpandable(
              isExpanded: false,
              expandIconSemanticLabel: 'Toggle graphics details',
              expandButtonPosition: YaruExpandableButtonPosition.end,
              header: const Text('Graphics details'),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Expected NVIDIA GPU: ${status.expectedState.label}'),
                    const SizedBox(height: 6),
                    Text(
                      'Supported choices: ${status.availableModes.where((mode) => mode != GraphicsMode.hybridAuto).map((mode) => mode.label).join(', ')}',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GraphicsFact extends StatelessWidget {
  const _GraphicsFact({
    required this.width,
    required this.label,
    required this.value,
  });

  final double width;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _ReconciliationBadge extends StatelessWidget {
  const _ReconciliationBadge({required this.status});

  final GraphicsModeStatus? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unsafeMode = status?.selectedMode == GraphicsMode.hybridAuto;
    final restartPending = status?.pendingMode != null;
    final settled =
        !unsafeMode &&
        !restartPending &&
        status?.reconciliation == GraphicsReconciliation.settled;
    final color = status == null
        ? scheme.onSurfaceVariant
        : settled
        ? const Color(0xff3FBF6F)
        : scheme.warning;
    final label = unsafeMode
        ? 'Unsafe mode'
        : restartPending
        ? 'Restart required'
        : status?.reconciliation.label ?? 'Unavailable';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ),
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
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
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
  const _DeactivateCard();

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
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Close GPU workloads, then restart the PCI device to recover from '
            'a stuck active state.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
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
                  'Privileged dGPU deactivation is not available in this build.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
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
                onPressed: null,
                icon: const Icon(Icons.close, size: 17),
                label: const Text('Kill processes'),
              ),
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.restart_alt, size: 17),
                label: const Text('Restart PCI device'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

double? _gpuUtilisation(SensorRecord record) => record.gpuUtilPercent;
double? _gpuTemperature(SensorRecord record) => record.dgpuTempC;
double? _gpuPower(SensorRecord record) => record.gpuPowerDrawW;
double? _igpuUtilisation(SensorRecord record) => record.igpuUtilPercent;
double? _igpuTemperature(SensorRecord record) => record.igpuTempC;

const _discreteHistoryOptions = [
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
];

const _integratedHistoryOptions = [
  TelemetrySeriesOption(
    label: 'Usage %',
    unit: '%',
    minimumY: 0,
    maximumY: 100,
    valueOf: _igpuUtilisation,
  ),
  TelemetrySeriesOption(
    label: 'Temperature',
    unit: '°C',
    valueOf: _igpuTemperature,
  ),
];

String _integratedProcessCount(GpuProcessScan? scan) {
  if (scan == null) return 'Unavailable';
  return switch (scan.reporting) {
    GpuProcessReporting.reported => '${scan.processes.length} running',
    GpuProcessReporting.notReported => 'Unavailable',
    GpuProcessReporting.noClients => 'None found',
  };
}

String _integratedProcessMessage(GpuProcessScan? scan) {
  if (scan == null) {
    return 'Process usage for the integrated GPU is unavailable.';
  }
  return switch (scan.reporting) {
    GpuProcessReporting.notReported =>
      'This kernel does not report which processes use the integrated GPU.',
    GpuProcessReporting.reported || GpuProcessReporting.noClients =>
      'No processes the app can inspect are using the integrated GPU.',
  };
}

String _measurement(double? value, String unit, int precision) =>
    value == null ? '—' : '${value.toStringAsFixed(precision)} $unit';

String _gpuDeviceLabel(String path) {
  final name = path.split('/').last;
  if (name.startsWith('card')) return 'Display ($name)';
  if (name.startsWith('renderD')) return 'Render ($name)';
  return 'NVIDIA driver ($name)';
}

String _vramLabel(double? used, double? total) {
  if (used == null || total == null) return '—';
  return '${used.toStringAsFixed(1)} / ${total.toStringAsFixed(1)} GB';
}

String _memoryLabel(int memoryMib) => memoryMib >= 1024
    ? '${(memoryMib / 1024).toStringAsFixed(1)} GB'
    : '$memoryMib MiB';
