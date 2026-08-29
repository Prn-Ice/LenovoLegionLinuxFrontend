import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/theme/legion_accent.dart';
import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/metric_gauge.dart';
import '../../../core/widgets/metric_text.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../../../core/widgets/surface_card.dart';
import '../../sensors/bloc/live_sensor_event.dart';
import '../../sensors/models/live_sensor_snapshot.dart';
import '../../sensors/providers/live_sensor_provider.dart';
import '../bloc/fans_bloc.dart';
import '../bloc/fans_event.dart';
import '../bloc/fans_state.dart';
import '../providers/fans_provider.dart';
import 'fan_curve_editor.dart';

class FansPage extends ConsumerStatefulWidget {
  const FansPage({super.key});

  @override
  ConsumerState<FansPage> createState() => _FansPageState();
}

class _FansPageState extends ConsumerState<FansPage> {
  FanChannel _channel = FanChannel.cpu;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveSensorBlocProvider.bloc).add(const LiveSensorStarted());
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fansBlocProvider);
    final sensors = ref.watch(liveSensorBlocProvider).snapshot;
    final bloc = ref.read(fansBlocProvider.bloc);
    final profile = _profileLabel(state.platformProfile);
    final selectedPreset = state.selectedPreset ?? state.recommendedPreset;
    final curveProfile = state.fanCurveDirty
        ? LegionAccent.custom.label
        : selectedPreset == null
        ? profile
        : _presetName(selectedPreset);
    final accent = state.fanCurveDirty
        ? LegionAccent.custom.color
        : _presetAccent(selectedPreset) ??
              LegionAccent.fromPowerModeValue(state.platformProfile)?.color ??
              LegionAccent.custom.color;

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    return AppPageBody(
      title: 'Fan curve',
      subtitle: Text('$profile profile | ${_powerLabel(state.onPowerSupply)}'),
      headerAction: AppRefreshButton(
        isBusy: state.isLoading,
        onPressed: state.isApplying
            ? null
            : () => bloc.add(const FansRefreshRequested()),
      ),
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        _FanActions(
          maximumFanSpeedEnabled: state.maximumFanSpeedEnabled,
          isApplying: state.isApplying,
          hasPresets: state.availablePresets.isNotEmpty,
          onMaximumFanSpeedPressed: () => _setMaximumFanSpeed(
            context,
            bloc,
            !(state.maximumFanSpeedEnabled ?? false),
          ),
          onApplyPresetPressed: () => _showPresetDialog(context, state, bloc),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final editor = state.fanCurve == null
                ? const _CurveUnavailable()
                : FanCurveEditor(
                    curve: state.fanCurve!,
                    channel: _channel,
                    profileLabel: curveProfile,
                    currentTemperature: _channel == FanChannel.cpu
                        ? sensors.cpuTempC
                        : sensors.gpuTempC,
                    accent: accent,
                    enabled: !state.isApplying,
                    dirty: state.fanCurveDirty,
                    isApplying: state.isApplying,
                    onChannelChanged: (channel) {
                      setState(() => _channel = channel);
                    },
                    onPointChanged: (index, point) => bloc.add(
                      FanCurvePointUpdated(index: index, point: point),
                    ),
                    onSave: state.fanCurveDirty && !state.isApplying
                        ? () => _saveCurve(context, bloc)
                        : null,
                  );
            final telemetry = _FanTelemetry(snapshot: sensors, accent: accent);

            if (constraints.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [editor, const SizedBox(height: 16), telemetry],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: editor),
                const SizedBox(width: 16),
                SizedBox(width: 260, child: telemetry),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _FanSafetyControls(state: state, bloc: bloc),
      ],
    );
  }

  Future<void> _setMaximumFanSpeed(
    BuildContext context,
    FansBloc bloc,
    bool enabled,
  ) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: enabled ? 'Enable maximum fan speed' : 'Disable maximum fan speed',
      message:
          'Maximum fan speed overrides normal curve control and may increase noise and power use. This change requires privileged access.',
      confirmLabel: enabled ? 'Enable' : 'Disable',
    );
    if (!context.mounted || !confirmed) return;
    bloc.add(MaximumFanSpeedSetRequested(enabled));
  }

  Future<void> _saveCurve(BuildContext context, FansBloc bloc) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Apply fan curve',
      message:
          'Writing the complete custom fan curve requires privileged access and may prompt for authentication.',
      confirmLabel: 'Apply curve',
    );
    if (!context.mounted || !confirmed) return;
    bloc.add(const FanCurveSaveRequested());
  }
}

class _FanActions extends StatelessWidget {
  const _FanActions({
    required this.maximumFanSpeedEnabled,
    required this.isApplying,
    required this.hasPresets,
    required this.onMaximumFanSpeedPressed,
    required this.onApplyPresetPressed,
  });

  final bool? maximumFanSpeedEnabled;
  final bool isApplying;
  final bool hasPresets;
  final VoidCallback onMaximumFanSpeedPressed;
  final VoidCallback onApplyPresetPressed;

  @override
  Widget build(BuildContext context) {
    final maximumSupported = maximumFanSpeedEnabled != null;
    final maximumEnabled = maximumFanSpeedEnabled == true;
    final maximumLabel = !maximumSupported
        ? 'Max Fan Speed unavailable'
        : maximumEnabled
        ? 'Max Fan: On'
        : 'Max Fan Speed';
    final maximumAction = maximumEnabled
        ? FilledButton.icon(
            key: const ValueKey('maximum-fan-speed'),
            onPressed: isApplying ? null : onMaximumFanSpeedPressed,
            icon: const Icon(Icons.air),
            label: Text(maximumLabel),
          )
        : OutlinedButton.icon(
            key: const ValueKey('maximum-fan-speed'),
            onPressed: !maximumSupported || isApplying
                ? null
                : onMaximumFanSpeedPressed,
            icon: const Icon(Icons.air),
            label: Text(maximumLabel),
          );
    final presetAction = FilledButton.icon(
      key: const ValueKey('apply-preset'),
      onPressed: !hasPresets || isApplying ? null : onApplyPresetPressed,
      icon: const Icon(Icons.tune),
      label: const Text('Apply Preset'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 48, child: maximumAction),
              const SizedBox(height: 10),
              SizedBox(height: 48, child: presetAction),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: SizedBox(height: 48, child: maximumAction)),
            const SizedBox(width: 12),
            Expanded(child: SizedBox(height: 48, child: presetAction)),
          ],
        );
      },
    );
  }
}

class _FanTelemetry extends StatelessWidget {
  const _FanTelemetry({required this.snapshot, required this.accent});

  final LiveSensorSnapshot snapshot;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.sensors, size: 20, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Live fan telemetry',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TelemetryChannel(
            label: 'CPU fan',
            rpm: snapshot.fan1Rpm,
            temperature: snapshot.cpuTempC,
            accent: accent,
          ),
          const Divider(height: 20),
          _TelemetryChannel(
            label: 'GPU fan',
            rpm: snapshot.fan2Rpm,
            temperature: snapshot.gpuTempC,
            accent: accent,
          ),
        ],
      ),
    );
  }
}

class _TelemetryChannel extends StatelessWidget {
  const _TelemetryChannel({
    required this.label,
    required this.rpm,
    required this.temperature,
    required this.accent,
  });

  final String label;
  final int? rpm;
  final double? temperature;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        MetricGauge(
          value: rpm?.toDouble(),
          min: 0,
          max: 5000,
          accent: accent,
          size: 88,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 3),
              Text(
                rpm == null ? 'Fan speed unavailable' : '$rpm RPM',
                style: monoMetaStyle(scheme),
              ),
              const SizedBox(height: 8),
              Text(
                temperature == null
                    ? 'Temperature unavailable'
                    : '${temperature!.round()}°C',
                style: monoBarStyle(scheme.onSurface),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CurveUnavailable extends StatelessWidget {
  const _CurveUnavailable();

  @override
  Widget build(BuildContext context) {
    return const SurfaceCard(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.multiline_chart, size: 36),
            SizedBox(height: 12),
            Text('Fan curve unavailable'),
            SizedBox(height: 4),
            Text(
              'The hwmon fan-curve interface was not detected on this device.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _FanSafetyControls extends StatelessWidget {
  const _FanSafetyControls({required this.state, required this.bloc});

  final FansState state;
  final FansBloc bloc;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Controller safeguards',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'These controller-level options require privileged access. Unsupported controls remain unavailable.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (state.isApplying)
            const _FanPrivilegeNotice(
              message:
                  'A fan-controller change is pending. Controls are temporarily locked.',
            )
          else
            const _FanPrivilegeNotice(message: 'Admin privileges required'),
          const SizedBox(height: 8),
          AppSwitchTile(
            value: state.miniFanCurveEnabled ?? false,
            onChanged: state.miniFanCurveEnabled != null && !state.isApplying
                ? (enabled) => _confirmToggle(
                    context,
                    title: 'Set Mini Fan Curve',
                    message:
                        'This changes the embedded controller fan behavior and requires privileged access.',
                    apply: () => bloc.add(MiniFanCurveSetRequested(enabled)),
                  )
                : null,
            title: 'Mini Fan Curve',
            subtitle: _capabilityDescription(
              state.miniFanCurveEnabled,
              'Enables the embedded controller mini fan curve during cool operation.',
              state.isApplying,
            ),
          ),
          AppSwitchTile(
            value: state.lockFanControllerEnabled ?? false,
            onChanged:
                state.lockFanControllerEnabled != null && !state.isApplying
                ? (enabled) => _confirmToggle(
                    context,
                    title: 'Set Lock Fan Controller',
                    message:
                        'Locking the embedded controller fan state requires privileged access. Disable it before returning fan control to another tool.',
                    apply: () =>
                        bloc.add(LockFanControllerSetRequested(enabled)),
                  )
                : null,
            title: 'Lock Fan Controller',
            subtitle: _capabilityDescription(
              state.lockFanControllerEnabled,
              'Locks the embedded controller fan-control state; disable it before another tool takes control.',
              state.isApplying,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmToggle(
    BuildContext context, {
    required String title,
    required String message,
    required VoidCallback apply,
  }) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: title,
      message: message,
      confirmLabel: 'Apply',
    );
    if (!context.mounted || !confirmed) return;
    apply();
  }
}

class _FanPrivilegeNotice extends StatelessWidget {
  const _FanPrivilegeNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.admin_panel_settings_outlined,
            size: 16,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showPresetDialog(
  BuildContext context,
  FansState state,
  FansBloc bloc,
) async {
  var selectedPreset = state.selectedPreset;
  final preset = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const YaruDialogTitleBar(title: Text('Choose fan preset')),
        titlePadding: EdgeInsets.zero,
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Select a profile and power context. The preset is not written until you choose Apply preset.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                RadioGroup<String>(
                  groupValue: selectedPreset,
                  onChanged: (candidate) {
                    if (candidate == null) return;
                    setDialogState(() => selectedPreset = candidate);
                  },
                  child: Column(
                    children: [
                      for (final candidate in state.availablePresets)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _PresetOption(
                            preset: candidate,
                            recommended: candidate == state.recommendedPreset,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: selectedPreset == null
                ? null
                : () => Navigator.of(dialogContext).pop(selectedPreset),
            child: const Text('Apply preset'),
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || preset == null) return;
  bloc.add(FansPresetSelectionChanged(preset));
  final confirmed = await confirmPrivilegedAction(
    context,
    title: 'Apply ${_presetName(preset)} preset',
    message:
        'Applying the ${_presetName(preset)} preset for ${_presetContext(preset).toLowerCase()} requires privileged access.',
    confirmLabel: 'Apply preset',
  );
  if (!context.mounted || !confirmed) return;
  bloc.add(const FansApplySelectedPresetRequested());
}

class _PresetOption extends StatelessWidget {
  const _PresetOption({required this.preset, required this.recommended});

  final String preset;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: recommended
          ? scheme.primary.withValues(alpha: 0.09)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: recommended
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: RadioListTile<String>(
        value: preset,
        title: Text(_presetName(preset)),
        subtitle: Text(
          recommended
              ? '${_presetContext(preset)} | Recommended for current context'
              : _presetContext(preset),
        ),
        secondary: recommended
            ? Icon(YaruIcons.star_filled, color: scheme.primary)
            : null,
      ),
    );
  }
}

String _profileLabel(String? profile) {
  if (profile == null || profile.trim().isEmpty) return 'Unknown';
  return profile
      .split('-')
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _powerLabel(bool? onPowerSupply) {
  if (onPowerSupply == null) return 'Power source unavailable';
  return onPowerSupply ? 'AC power' : 'Battery power';
}

String _presetName(String preset) {
  final parts = preset.split('-');
  if (parts.isNotEmpty && (parts.last == 'ac' || parts.last == 'battery')) {
    parts.removeLast();
  }
  if (parts.join('-') == 'balanced-performance') return 'Custom';
  return parts
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _presetContext(String preset) {
  if (preset.endsWith('-ac')) return 'AC power';
  if (preset.endsWith('-battery')) return 'Battery power';
  return 'All power contexts';
}

Color? _presetAccent(String? preset) {
  if (preset == null || preset.isEmpty) return null;
  final mode = preset
      .replaceFirst(RegExp(r'-(ac|battery)$'), '')
      .replaceFirst('balanced-performance', 'custom');
  return LegionAccent.fromPowerModeValue(mode)?.color;
}

String _capabilityDescription(bool? value, String description, bool applying) {
  if (value == null) return 'Unsupported on this device. $description';
  if (applying) return 'Change pending. $description';
  return '${value ? 'Enabled' : 'Disabled'}. $description';
}
