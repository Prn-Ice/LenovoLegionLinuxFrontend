import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/theme/legion_accent.dart';
import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../../sensors/bloc/live_sensor_event.dart';
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
    final selectedPreset = state.selectedPreset ?? state.recommendedPreset;
    final accent = LegionAccent.custom.color;
    final hasFanControls =
        state.miniFanCurveEnabled != null ||
        state.maximumFanSpeedEnabled != null ||
        state.lockFanControllerEnabled != null;
    final currentTemperature = _channel == FanChannel.cpu
        ? sensors.cpuTempC
        : sensors.gpuTempC;
    final currentRpm = _channel == FanChannel.cpu
        ? sensors.fan1Rpm
        : sensors.fan2Rpm ?? sensors.gpuFanRpm;

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    return AppPageBody(
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        _FanWorkspaceToolbar(
          channel: _channel,
          availablePresets: state.availablePresets,
          selectedPreset: selectedPreset,
          recommendedPreset: state.recommendedPreset,
          onPowerSupply: state.onPowerSupply,
          isApplying: state.isApplying,
          onChannelChanged: (channel) => setState(() => _channel = channel),
          onPresetSelected: (preset) => _applyPreset(context, preset, bloc),
        ),
        const SizedBox(height: 16),
        if (state.fanCurve == null)
          FanCurveUnavailablePanel(
            channel: _channel,
            currentTemperature: currentTemperature,
            currentRpm: currentRpm,
            accent: accent,
          )
        else
          FanCurveEditor(
            curve: state.fanCurve!,
            channel: _channel,
            currentTemperature: currentTemperature,
            currentRpm: currentRpm,
            accent: accent,
            enabled: !state.isApplying,
            dirty: state.fanCurveDirty,
            isApplying: state.isApplying,
            onPointChanged: (index, point) =>
                bloc.add(FanCurvePointUpdated(index: index, point: point)),
            onSave: state.fanCurveDirty && !state.isApplying
                ? () => _saveCurve(context, bloc)
                : null,
          ),
        if (hasFanControls) ...[
          const SizedBox(height: 16),
          _FanControls(
            state: state,
            onMiniFanCurveChanged: (enabled) =>
                _setMiniFanCurve(context, bloc, enabled),
            onMaximumFanSpeedChanged: (enabled) =>
                _setMaximumFanSpeed(context, bloc, enabled),
            onLockFanControllerChanged: (enabled) =>
                _setLockFanController(context, bloc, enabled),
          ),
        ],
      ],
    );
  }

  Future<void> _applyPreset(
    BuildContext context,
    String preset,
    FansBloc bloc,
  ) async {
    bloc.add(FansPresetSelectionChanged(preset));
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Apply ${_presetDisplayName(preset)} preset',
      message:
          'Applying the ${_presetDisplayName(preset)} preset for ${_presetContext(preset).toLowerCase()} requires privileged access.',
      confirmLabel: 'Apply preset',
    );
    if (!context.mounted || !confirmed) return;
    bloc.add(const FansApplySelectedPresetRequested());
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

  Future<void> _setMiniFanCurve(
    BuildContext context,
    FansBloc bloc,
    bool enabled,
  ) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Set mini fan curve',
      message:
          'This changes the embedded controller fan behavior and requires privileged access.',
      confirmLabel: 'Apply',
    );
    if (!context.mounted || !confirmed) return;
    bloc.add(MiniFanCurveSetRequested(enabled));
  }

  Future<void> _setLockFanController(
    BuildContext context,
    FansBloc bloc,
    bool enabled,
  ) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Set lock fan controller',
      message:
          'Locking the embedded controller fan state requires privileged access. Disable it before returning fan control to another tool.',
      confirmLabel: 'Apply',
    );
    if (!context.mounted || !confirmed) return;
    bloc.add(LockFanControllerSetRequested(enabled));
  }
}

class _FanWorkspaceToolbar extends StatelessWidget {
  const _FanWorkspaceToolbar({
    required this.channel,
    required this.availablePresets,
    required this.selectedPreset,
    required this.recommendedPreset,
    required this.onPowerSupply,
    required this.isApplying,
    required this.onChannelChanged,
    required this.onPresetSelected,
  });

  final FanChannel channel;
  final List<String> availablePresets;
  final String? selectedPreset;
  final String? recommendedPreset;
  final bool? onPowerSupply;
  final bool isApplying;
  final ValueChanged<FanChannel> onChannelChanged;
  final ValueChanged<String> onPresetSelected;

  @override
  Widget build(BuildContext context) {
    final suffix = switch (onPowerSupply) {
      true => '-ac',
      false => '-battery',
      null => null,
    };
    final contextualPresets = suffix == null
        ? availablePresets
        : availablePresets
              .where((preset) => preset.endsWith(suffix))
              .toList(growable: false);
    final visiblePresets = contextualPresets.isEmpty
        ? availablePresets
        : contextualPresets;

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(
          context,
        ).colorScheme.copyWith(primary: LegionAccent.custom.color),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final channelPicker = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ToggleButtons(
              key: const ValueKey('fan-channel-toggle'),
              isSelected: [
                for (final candidate in FanChannel.values) candidate == channel,
              ],
              onPressed: isApplying
                  ? null
                  : (index) => onChannelChanged(FanChannel.values[index]),
              children: [
                for (final candidate in FanChannel.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Text(candidate.label),
                  ),
              ],
            ),
          );
          final presetPicker = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in visiblePresets)
                ChoiceChip(
                  key: ValueKey('fan-preset-$preset'),
                  selected: preset == selectedPreset,
                  onSelected: isApplying
                      ? null
                      : (_) => onPresetSelected(preset),
                  avatar: preset == recommendedPreset
                      ? const Icon(YaruIcons.star_filled, size: 15)
                      : null,
                  label: Text(
                    suffix == null
                        ? '${_presetDisplayName(preset)} (${_presetContextLabel(preset)})'
                        : _presetDisplayName(preset),
                  ),
                ),
            ],
          );

          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                channelPicker,
                const SizedBox(height: 12),
                presetPicker,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              channelPicker,
              const SizedBox(width: 20),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: presetPicker,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FanControls extends StatelessWidget {
  const _FanControls({
    required this.state,
    required this.onMiniFanCurveChanged,
    required this.onMaximumFanSpeedChanged,
    required this.onLockFanControllerChanged,
  });

  final FansState state;
  final ValueChanged<bool> onMiniFanCurveChanged;
  final ValueChanged<bool> onMaximumFanSpeedChanged;
  final ValueChanged<bool> onLockFanControllerChanged;

  @override
  Widget build(BuildContext context) {
    final controls = <Widget>[
      if (state.miniFanCurveEnabled case final value?)
        AppSwitchTile(
          key: const ValueKey('mini-fan-curve'),
          value: value,
          onChanged: state.isApplying ? null : onMiniFanCurveChanged,
          title: 'Reduce fan cycling',
          subtitle: state.isApplying
              ? 'Applying change...'
              : "Use the controller's low-temperature fan behavior.",
        ),
      if (state.maximumFanSpeedEnabled case final value?)
        AppSwitchTile(
          key: const ValueKey('maximum-fan-speed'),
          value: value,
          onChanged: state.isApplying ? null : onMaximumFanSpeedChanged,
          title: 'Maximum fan speed',
          subtitle: state.isApplying
              ? 'Applying change...'
              : 'Run both fans at full speed until disabled.',
        ),
      if (state.lockFanControllerEnabled case final value?)
        AppSwitchTile(
          value: value,
          onChanged: state.isApplying ? null : onLockFanControllerChanged,
          title: 'Exclusive fan control',
          subtitle: state.isApplying
              ? 'Applying change...'
              : 'Prevent other tools from changing fan settings.',
        ),
    ];

    return AppSectionCard(
      title: 'Fan controls',
      children: [
        for (var i = 0; i < controls.length; i++) ...[
          controls[i],
          if (i != controls.length - 1) const Divider(height: 1),
        ],
      ],
    );
  }
}

String _presetDisplayName(String preset) {
  final parts = preset.split('-');
  if (parts.isNotEmpty && (parts.last == 'ac' || parts.last == 'battery')) {
    parts.removeLast();
  }
  switch (parts.join('-')) {
    case 'quiet':
      return 'Silent';
    case 'performance':
      return 'Aggressive';
    case 'balanced-performance':
      return 'Custom';
  }
  return parts
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _presetContext(String preset) {
  if (preset.endsWith('-ac')) return 'AC power';
  if (preset.endsWith('-battery')) return 'Battery power';
  return 'All power contexts';
}

String _presetContextLabel(String preset) {
  if (preset.endsWith('-ac')) return 'AC';
  if (preset.endsWith('-battery')) return 'battery';
  return 'all power';
}
