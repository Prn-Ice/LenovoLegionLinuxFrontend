import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/models/cpu_policy_snapshot.dart';
import '../../../core/theme/legion_accent.dart';
import '../../../core/models/power_profiles_daemon_snapshot.dart';
import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/metric_text.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../../../core/widgets/surface_card.dart';
import '../../dashboard/widgets/mode_hero.dart';
import '../../dashboard/widgets/quick_controls.dart';
import '../../sensors/bloc/live_sensor_event.dart';
import '../../sensors/providers/live_sensor_provider.dart';
import '../bloc/power_bloc.dart';
import '../bloc/power_event.dart';
import '../bloc/power_state.dart';
import '../models/power_limit.dart';
import '../models/power_mode.dart';
import '../providers/power_provider.dart';

class PowerPage extends ConsumerStatefulWidget {
  const PowerPage({super.key});

  @override
  ConsumerState<PowerPage> createState() => _PowerPageState();
}

class _PowerPageState extends ConsumerState<PowerPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveSensorBlocProvider.bloc).add(const LiveSensorStarted());
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(powerBlocProvider);
    final sensors = ref.watch(liveSensorBlocProvider).snapshot;
    final bloc = ref.read(powerBlocProvider.bloc);
    final accent =
        LegionAccent.fromPowerModeValue(state.currentMode?.value)?.color ??
        Theme.of(context).colorScheme.primary;

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    return AppPageBody(
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        ModeHero(
          accent: accent,
          availableModes: state.availableModes
              .map((mode) => mode.value)
              .toList(growable: false),
          selectedMode: state.currentMode?.value,
          isApplying: state.isApplying,
          onModeSelected: (index) =>
              _selectMode(bloc, state, state.availableModes[index]),
        ),
        const SizedBox(height: 12),
        _CpuPolicyDetailsCard(
          daemon: state.daemonSnapshot,
          cpuPolicy: state.cpuPolicy,
          currentMode: state.currentMode,
          averageClockGhz: sensors.cpuClockGhz,
          packagePowerW: sensors.cpuPackagePowerW,
        ),
        const SizedBox(height: 16),
        _PowerLimitsCard(
          readings: state.powerLimits,
          accent: accent,
          isApplying: state.isApplying,
          canEdit:
              state.currentMode?.isCustom == true &&
              state.onPowerSupply == true,
          blockReason: _limitBlockReason(state),
          onValueRequested: (reading) => _promptLimit(context, reading),
          onApplyRequested: (readings) => _applyPowerLimits(bloc, readings),
        ),
        if (state.cpuOverclockEnabled != null ||
            state.gpuOverclockEnabled != null) ...[
          const SizedBox(height: 16),
          _OverclockingCard(
            state: state,
            accent: accent,
            onCpuChanged: (enabled) => _setCpuOverclock(context, bloc, enabled),
            onGpuChanged: (enabled) => _setGpuOverclock(context, bloc, enabled),
          ),
        ],
      ],
    );
  }

  void _selectMode(PowerBloc bloc, PowerState state, PowerMode selected) {
    if (selected == state.currentMode || state.isApplying) return;
    bloc.add(PowerModeSetRequested(selected));
  }

  Future<void> _setCpuOverclock(
    BuildContext context,
    PowerBloc bloc,
    bool enabled,
  ) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: '${enabled ? 'Enable' : 'Disable'} CPU overclock',
      message:
          'CPU overclocking can increase heat, power use, and instability. This change requires privileged access.',
      confirmLabel: enabled ? 'Enable' : 'Disable',
    );
    if (!context.mounted || !confirmed) return;
    bloc.add(CpuOverclockSetRequested(enabled));
  }

  Future<void> _setGpuOverclock(
    BuildContext context,
    PowerBloc bloc,
    bool enabled,
  ) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: '${enabled ? 'Enable' : 'Disable'} GPU overclock',
      message:
          'GPU overclocking can increase heat, power use, and instability. This change requires privileged access.',
      confirmLabel: enabled ? 'Enable' : 'Disable',
    );
    if (!context.mounted || !confirmed) return;
    bloc.add(GpuOverclockSetRequested(enabled));
  }

  String? _limitBlockReason(PowerState state) {
    if (state.currentMode?.isCustom != true) {
      return 'Switch to Custom mode to edit controller power limits.';
    }
    if (state.onPowerSupply == false) {
      return 'Connect AC power to edit custom power limits.';
    }
    if (state.onPowerSupply == null) {
      return 'AC power status is unavailable, so limit changes are disabled.';
    }
    return null;
  }

  Future<int?> _promptLimit(
    BuildContext context,
    PowerLimitReading reading,
  ) async {
    final controller = TextEditingController(text: '${reading.value}');
    String? errorText;

    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: YaruDialogTitleBar(title: Text(reading.spec.label)),
          titlePadding: EdgeInsets.zero,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Allowed range: ${reading.spec.effectiveMin}-${reading.spec.max} ${reading.spec.unit}',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Value (${reading.spec.unit})',
                  errorText: errorText,
                ),
                onSubmitted: (_) => _submitLimitDialog(
                  dialogContext,
                  controller,
                  reading.spec,
                  (message) => setDialogState(() => errorText = message),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => _submitLimitDialog(
                dialogContext,
                controller,
                reading.spec,
                (message) => setDialogState(() => errorText = message),
              ),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();

    return result;
  }

  void _submitLimitDialog(
    BuildContext context,
    TextEditingController controller,
    PowerLimitSpec spec,
    ValueChanged<String?> setError,
  ) {
    final parsed = int.tryParse(controller.text.trim());
    if (parsed == null) {
      setError('Enter a whole number.');
      return;
    }
    if (parsed < spec.effectiveMin || parsed > spec.max) {
      setError('Enter a value from ${spec.effectiveMin} to ${spec.max}.');
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  Future<bool> _applyPowerLimits(
    PowerBloc bloc,
    List<PowerLimitReading> readings,
  ) async {
    if (readings.isEmpty) return false;
    bloc.add(PowerLimitsApplyRequested(readings));
    return true;
  }
}

class _CpuPolicyDetailsCard extends StatelessWidget {
  const _CpuPolicyDetailsCard({
    required this.daemon,
    required this.cpuPolicy,
    required this.currentMode,
    required this.averageClockGhz,
    required this.packagePowerW,
  });

  final PowerProfilesDaemonSnapshot? daemon;
  final CpuPolicySnapshot? cpuPolicy;
  final PowerMode? currentMode;
  final double? averageClockGhz;
  final double? packagePowerW;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final facts = _facts();

    return SurfaceCard(
      key: const ValueKey('cpu-policy-details-card'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('CPU policy details', style: textTheme.titleMedium),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              if (facts.isEmpty) {
                return Text(
                  'CPU policy details are unavailable.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                );
              }
              final width = constraints.maxWidth < 520
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 16) / 2;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final fact in facts)
                    SizedBox(
                      width: width,
                      child: _PowerPolicyFact(
                        label: fact.label,
                        value: fact.value,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  List<({String label, String value})> _facts() {
    final facts = <({String label, String value})>[];
    final daemonSnapshot = daemon;
    final policy = cpuPolicy;
    final cpuDrivers = daemonSnapshot?.cpuDrivers ?? const <String>[];
    final platformDrivers = daemonSnapshot?.platformDrivers ?? const <String>[];

    facts.add((
      label: 'Average clock',
      value: averageClockGhz == null
          ? 'Unavailable'
          : '${averageClockGhz!.toStringAsFixed(2)} GHz',
    ));
    facts.add((
      label: 'CPU package power',
      value: packagePowerW == null
          ? 'Unavailable'
          : '${packagePowerW!.toStringAsFixed(1)} W',
    ));

    if (daemonSnapshot != null) {
      facts.add((
        label: 'Service',
        value: daemonSnapshot.version == null
            ? 'Power Profiles Daemon'
            : 'PPD ${daemonSnapshot.version}',
      ));
      facts.add((
        label: 'CPU profile',
        value: humanizeMode(daemonSnapshot.activeProfile),
      ));
    }
    if (policy?.driver case final driver?) {
      final status = policy?.pstateStatus;
      facts.add((
        label: 'CPU driver',
        value: status == null ? driver : '$driver ($status)',
      ));
    } else if (cpuDrivers.isNotEmpty) {
      facts.add((label: 'CPU driver', value: cpuDrivers.join(', ')));
    }
    if (platformDrivers.isNotEmpty) {
      facts.add((label: 'Firmware driver', value: platformDrivers.join(', ')));
    }
    if (policy?.governor case final governor?) {
      facts.add((label: 'Governor', value: governor));
    }
    if (policy?.energyPerformancePreference case final preference?) {
      facts.add((label: 'Energy preference', value: preference));
    }
    if (policy?.boostEnabled case final boost?) {
      facts.add((label: 'Boost', value: boost ? 'Enabled' : 'Disabled'));
    }
    final minimum = policy?.minimumFrequencyKhz;
    final maximum = policy?.maximumFrequencyKhz;
    if (minimum != null && maximum != null) {
      facts.add((
        label: 'Frequency policy',
        value: '${(minimum / 1000).round()}-${(maximum / 1000).round()} MHz',
      ));
    }
    if (currentMode case final mode?) {
      facts.add((label: 'Firmware profile', value: modeLabel(mode.value)));
    }
    if (daemonSnapshot?.batteryAware case final batteryAware?) {
      facts.add((
        label: 'Battery aware',
        value: batteryAware ? 'Enabled' : 'Disabled',
      ));
    }
    if (daemonSnapshot?.performanceDegraded?.trim() case final reason?
        when reason.isNotEmpty) {
      facts.add((label: 'Performance limited', value: reason));
    }
    return facts;
  }
}

class _PowerPolicyFact extends StatelessWidget {
  const _PowerPolicyFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: monoFactStyle(scheme)),
        ],
      ),
    );
  }
}

class _PowerLimitsCard extends StatefulWidget {
  const _PowerLimitsCard({
    required this.readings,
    required this.accent,
    required this.isApplying,
    required this.canEdit,
    required this.blockReason,
    required this.onValueRequested,
    required this.onApplyRequested,
  });

  final List<PowerLimitReading> readings;
  final Color accent;
  final bool isApplying;
  final bool canEdit;
  final String? blockReason;
  final Future<int?> Function(PowerLimitReading) onValueRequested;
  final Future<bool> Function(List<PowerLimitReading>) onApplyRequested;

  @override
  State<_PowerLimitsCard> createState() => _PowerLimitsCardState();
}

class _PowerLimitsCardState extends State<_PowerLimitsCard> {
  static const _primaryIds = {'cpu_longterm', 'cpu_shortterm', 'gpu_ctgp'};

  final Map<String, int> _drafts = {};

  bool get _dirty => _drafts.isNotEmpty;

  @override
  void didUpdateWidget(covariant _PowerLimitsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = {
      for (final reading in widget.readings) reading.spec.id: reading.value,
    };
    _drafts.removeWhere(
      (id, value) => !current.containsKey(id) || current[id] == value,
    );
  }

  int _valueFor(PowerLimitReading reading) =>
      _drafts[reading.spec.id] ?? reading.value;

  void _stage(PowerLimitReading reading, int value) {
    setState(() {
      if (value == reading.value) {
        _drafts.remove(reading.spec.id);
      } else {
        _drafts[reading.spec.id] = value;
      }
    });
  }

  List<PowerLimitReading> _stagedReadings() => [
    for (final reading in widget.readings)
      if (_drafts[reading.spec.id] case final value?)
        PowerLimitReading(
          spec: reading.spec,
          value: value,
          hardwareDefault: reading.hardwareDefault,
        ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final primary = widget.readings
        .where((reading) => _primaryIds.contains(reading.spec.id))
        .toList(growable: false);
    final additional = widget.readings
        .where((reading) => !_primaryIds.contains(reading.spec.id))
        .toList(growable: false);
    final hasWritableLimits = widget.readings.any(
      (reading) => reading.spec.isWritable,
    );
    final blockReason = hasWritableLimits ? widget.blockReason : null;

    return SurfaceCard(
      key: const ValueKey('power-limits-card'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Power limits', style: textTheme.titleMedium),
              ),
              if (hasWritableLimits)
                Text(
                  'Custom mode only',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.56),
                  ),
                ),
            ],
          ),
          if (widget.readings.isEmpty) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(YaruIcons.information, size: 19, color: widget.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The platform controller did not provide usable power-limit values.',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Controller values are read from firmware. Hardware defaults are shown only when verified for this model.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            if (blockReason case final reason?) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(YaruIcons.warning, size: 18, color: scheme.warning),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      reason,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            for (var i = 0; i < primary.length; i++) ...[
              const SizedBox(height: 18),
              _PowerLimitSlider(
                reading: PowerLimitReading(
                  spec: primary[i].spec,
                  value: _valueFor(primary[i]),
                  hardwareDefault: primary[i].hardwareDefault,
                ),
                accent: widget.accent,
                enabled: widget.canEdit && !widget.isApplying,
                onChanged: (value) => _stage(primary[i], value),
              ),
            ],
            if (additional.isNotEmpty) ...[
              const SizedBox(height: 14),
              YaruExpandable(
                isExpanded: false,
                expandButtonPosition: YaruExpandableButtonPosition.end,
                header: Text('Additional limits (${additional.length})'),
                child: Column(
                  children: [
                    for (final reading in additional)
                      YaruListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(reading.spec.label),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              reading.spec.isWritable
                                  ? 'Editable range: ${reading.spec.effectiveMin}-${reading.spec.max} ${reading.spec.unit}'
                                  : 'Reported by the controller · Read-only',
                            ),
                            Text(_hardwareDefaultLabel(reading)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_valueFor(reading)} ${reading.spec.unit}',
                              style: monoStatValueStyle,
                            ),
                            if (reading.spec.isWritable) ...[
                              const SizedBox(width: 12),
                              OutlinedButton(
                                onPressed: !widget.canEdit || widget.isApplying
                                    ? null
                                    : () async {
                                        final value = await widget
                                            .onValueRequested(
                                              PowerLimitReading(
                                                spec: reading.spec,
                                                value: _valueFor(reading),
                                                hardwareDefault:
                                                    reading.hardwareDefault,
                                              ),
                                            );
                                        if (value != null && mounted) {
                                          _stage(reading, value);
                                        }
                                      },
                                child: const Text('Set'),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (hasWritableLimits) ...[
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  Text(
                    _dirty ? 'Unsaved limit changes' : 'No staged changes',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.68),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: _dirty && !widget.isApplying
                            ? () => setState(_drafts.clear)
                            : null,
                        child: const Text('Revert'),
                      ),
                      FilledButton(
                        onPressed:
                            _dirty && widget.canEdit && !widget.isApplying
                            ? () => widget.onApplyRequested(_stagedReadings())
                            : null,
                        child: widget.isApplying
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Apply changes'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PowerLimitSlider extends StatelessWidget {
  const _PowerLimitSlider({
    required this.reading,
    required this.accent,
    required this.enabled,
    required this.onChanged,
  });

  final PowerLimitReading reading;
  final Color accent;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spec = reading.spec;
    final value = reading.value.clamp(spec.effectiveMin, spec.max).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(spec.label)),
            Text('${value.round()} ${spec.unit}', style: monoStatValueStyle),
          ],
        ),
        const SizedBox(height: 2),
        Text(_hardwareDefaultLabel(reading), style: monoMetaStyle(scheme)),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accent,
            thumbColor: accent,
            overlayColor: accent.withValues(alpha: 0.12),
            inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.1),
          ),
          child: Slider(
            key: ValueKey('power-limit-slider-${spec.id}'),
            value: value,
            min: spec.effectiveMin.toDouble(),
            max: spec.max.toDouble(),
            divisions: spec.max - spec.effectiveMin,
            label: '${value.round()} ${spec.unit}',
            onChanged: enabled ? (value) => onChanged(value.round()) : null,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${spec.effectiveMin} ${spec.unit}',
              style: monoMetaStyle(scheme),
            ),
            Text('${spec.max} ${spec.unit}', style: monoMetaStyle(scheme)),
          ],
        ),
      ],
    );
  }
}

String _hardwareDefaultLabel(PowerLimitReading reading) {
  final value = reading.hardwareDefault;
  return value == null
      ? 'Hardware default unavailable'
      : 'Hardware default: $value ${reading.spec.unit}';
}

class _OverclockingCard extends StatelessWidget {
  const _OverclockingCard({
    required this.state,
    required this.accent,
    required this.onCpuChanged,
    required this.onGpuChanged,
  });

  final PowerState state;
  final Color accent;
  final ValueChanged<bool> onCpuChanged;
  final ValueChanged<bool> onGpuChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      key: const ValueKey('overclocking-card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Advanced tuning', style: textTheme.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: 12),
        QuickControls(
          accent: accent,
          controls: [
            if (state.cpuOverclockEnabled case final value?)
              QuickControl(
                widgetKey: const ValueKey('cpu-overclock'),
                icon: YaruIcons.computer,
                value: value,
                onChanged: state.isApplying ? null : onCpuChanged,
                title: 'CPU overclock',
                subtitle: value ? 'Enabled' : 'Disabled',
              ),
            if (state.gpuOverclockEnabled case final value?)
              QuickControl(
                widgetKey: const ValueKey('gpu-overclock'),
                icon: YaruIcons.video,
                value: value,
                onChanged: state.isApplying ? null : onGpuChanged,
                title: 'GPU overclock',
                subtitle: value ? 'Enabled' : 'Disabled',
              ),
          ],
        ),
      ],
    );
  }
}
