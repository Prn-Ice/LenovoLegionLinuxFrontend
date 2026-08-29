import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/theme/legion_accent.dart';
import '../../../core/models/power_profiles_daemon_snapshot.dart';
import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/metric_text.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../../../core/widgets/surface_card.dart';
import '../../dashboard/widgets/mode_hero.dart';
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
  Widget build(BuildContext context) {
    final state = ref.watch(powerBlocProvider);
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
              _selectMode(context, bloc, state, state.availableModes[index]),
        ),
        const SizedBox(height: 12),
        _PowerProfileStatus(
          daemon: state.daemonSnapshot,
          onPowerSupply: state.onPowerSupply,
          accent: accent,
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
          onApplyRequested: (readings) =>
              _applyPowerLimits(context, bloc, readings),
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

  Future<void> _selectMode(
    BuildContext context,
    PowerBloc bloc,
    PowerState state,
    PowerMode selected,
  ) async {
    if (selected == state.currentMode || state.isApplying) return;
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Set ${selected.label} mode',
      message:
          '${selected.description}. Changing the platform power profile requires privileged access.',
      confirmLabel: 'Set mode',
    );
    if (!context.mounted || !confirmed) return;
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
                'Allowed range: ${reading.spec.min}-${reading.spec.max} ${reading.spec.unit}',
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
    if (parsed < spec.min || parsed > spec.max) {
      setError('Enter a value from ${spec.min} to ${spec.max}.');
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  Future<bool> _applyPowerLimits(
    BuildContext context,
    PowerBloc bloc,
    List<PowerLimitReading> readings,
  ) async {
    if (readings.isEmpty) return false;
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Apply custom power limits',
      message:
          'Apply ${readings.length} staged ${readings.length == 1 ? 'limit' : 'limits'} to the controller. Custom mode and AC power must remain active.',
      confirmLabel: 'Apply changes',
    );
    if (!context.mounted || !confirmed) return false;
    bloc.add(PowerLimitsApplyRequested(readings));
    return true;
  }
}

class _PowerProfileStatus extends StatelessWidget {
  const _PowerProfileStatus({
    required this.daemon,
    required this.onPowerSupply,
    required this.accent,
  });

  final PowerProfilesDaemonSnapshot? daemon;
  final bool? onPowerSupply;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final daemonSnapshot = daemon;
    final available = daemonSnapshot != null;
    final drivers = available
        ? <String>{
            ...daemonSnapshot.cpuDrivers,
            ...daemonSnapshot.platformDrivers,
          }.join(' + ')
        : '';

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final powerLabel = onPowerSupply == null
              ? 'Power unknown'
              : onPowerSupply!
              ? 'On AC power'
              : 'On battery';
          final details = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  available
                      ? 'Power Profiles Daemon active'
                      : 'Direct platform control',
                  style: textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  available
                      ? 'Standard modes synchronize CPU policy and firmware${drivers.isEmpty ? '' : ' through $drivers'}.'
                      : 'The daemon is unavailable; standard modes cannot coordinate amd-pstate automatically.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          );
          final icon = Icon(
            available ? YaruIcons.ok : YaruIcons.warning,
            size: 18,
            color: available ? accent : scheme.error,
          );
          final power = Text(
            powerLabel,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.68),
            ),
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: 10),
              if (constraints.maxWidth < 360)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [details]),
                      const SizedBox(height: 8),
                      power,
                    ],
                  ),
                )
              else ...[
                details,
                const SizedBox(width: 12),
                power,
              ],
            ],
          );
        },
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
        PowerLimitReading(spec: reading.spec, value: value),
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
              if (widget.readings.isNotEmpty)
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
                    'The platform controller does not expose adjustable power limits.',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            if (widget.blockReason case final reason?) ...[
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
                        subtitle: Text(
                          '${reading.spec.min}-${reading.spec.max} ${reading.spec.unit}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_valueFor(reading)} ${reading.spec.unit}',
                              style: monoStatValueStyle,
                            ),
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
                                            ),
                                          );
                                      if (value != null && mounted) {
                                        _stage(reading, value);
                                      }
                                    },
                              child: const Text('Set'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
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
                      onPressed: _dirty && widget.canEdit && !widget.isApplying
                          ? () => widget.onApplyRequested(_stagedReadings())
                          : null,
                      child: widget.isApplying
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Apply changes'),
                    ),
                  ],
                ),
              ],
            ),
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
    final value = reading.value.clamp(spec.min, spec.max).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(spec.label)),
            Text('${value.round()} ${spec.unit}', style: monoStatValueStyle),
          ],
        ),
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
            min: spec.min.toDouble(),
            max: spec.max.toDouble(),
            divisions: spec.max - spec.min,
            label: '${value.round()} ${spec.unit}',
            onChanged: enabled ? (value) => onChanged(value.round()) : null,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${spec.min} ${spec.unit}', style: monoMetaStyle(scheme)),
            Text('${spec.max} ${spec.unit}', style: monoMetaStyle(scheme)),
          ],
        ),
      ],
    );
  }
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SurfaceCard(
      key: const ValueKey('overclocking-card'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(YaruIcons.gears, size: 19, color: accent),
              const SizedBox(width: 9),
              Expanded(
                child: Text('Advanced tuning', style: textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Overclocking can increase temperature, power use, and instability.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          if (state.cpuOverclockEnabled case final value?)
            AppSwitchTile(
              value: value,
              onChanged: state.isApplying ? null : onCpuChanged,
              title: 'CPU overclock',
              subtitle: value ? 'Enabled' : 'Disabled',
            ),
          if (state.gpuOverclockEnabled case final value?)
            AppSwitchTile(
              value: value,
              onChanged: state.isApplying ? null : onGpuChanged,
              title: 'GPU overclock',
              subtitle: value ? 'Enabled' : 'Disabled',
            ),
        ],
      ),
    );
  }
}
