import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/theme/legion_accent.dart';
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

class PowerPage extends ConsumerWidget {
  const PowerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        const SizedBox(height: 16),
        _PowerLimitsCard(
          readings: state.powerLimits,
          accent: accent,
          isApplying: state.isApplying,
          onSliderChanged: (reading, value) =>
              _confirmAndSetLimit(context, bloc, reading, value),
          onSetRequested: (reading) =>
              _promptAndSetLimit(context, bloc, reading),
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

  Future<void> _promptAndSetLimit(
    BuildContext context,
    PowerBloc bloc,
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

    if (result == null || !context.mounted) return;
    await _confirmAndSetLimit(context, bloc, reading, result);
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

  Future<bool> _confirmAndSetLimit(
    BuildContext context,
    PowerBloc bloc,
    PowerLimitReading reading,
    int value,
  ) async {
    if (value == reading.value) return false;
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Set ${reading.spec.label}',
      message:
          'Change ${reading.spec.label} from ${reading.value} to $value ${reading.spec.unit}. This requires privileged access.',
      confirmLabel: 'Apply limit',
    );
    if (!context.mounted || !confirmed) return false;
    bloc.add(PowerLimitSetRequested(limit: reading.spec, value: value));
    return true;
  }
}

class _PowerLimitsCard extends StatelessWidget {
  const _PowerLimitsCard({
    required this.readings,
    required this.accent,
    required this.isApplying,
    required this.onSliderChanged,
    required this.onSetRequested,
  });

  static const _primaryIds = {'cpu_longterm', 'cpu_shortterm', 'gpu_ctgp'};

  final List<PowerLimitReading> readings;
  final Color accent;
  final bool isApplying;
  final Future<bool> Function(PowerLimitReading, int) onSliderChanged;
  final ValueChanged<PowerLimitReading> onSetRequested;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final primary = readings
        .where((reading) => _primaryIds.contains(reading.spec.id))
        .toList(growable: false);
    final additional = readings
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
              if (readings.isNotEmpty)
                Text(
                  '${readings.length} available',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.56),
                  ),
                ),
            ],
          ),
          if (readings.isEmpty) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(YaruIcons.information, size: 19, color: accent),
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
            for (var i = 0; i < primary.length; i++) ...[
              const SizedBox(height: 18),
              _PowerLimitSlider(
                reading: primary[i],
                accent: accent,
                isApplying: isApplying,
                onChanged: (value) => onSliderChanged(primary[i], value),
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
                              '${reading.value} ${reading.spec.unit}',
                              style: monoStatValueStyle,
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: isApplying
                                  ? null
                                  : () => onSetRequested(reading),
                              child: const Text('Set'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PowerLimitSlider extends StatefulWidget {
  const _PowerLimitSlider({
    required this.reading,
    required this.accent,
    required this.isApplying,
    required this.onChanged,
  });

  final PowerLimitReading reading;
  final Color accent;
  final bool isApplying;
  final Future<bool> Function(int) onChanged;

  @override
  State<_PowerLimitSlider> createState() => _PowerLimitSliderState();
}

class _PowerLimitSliderState extends State<_PowerLimitSlider> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = _clampedValue(widget.reading);
  }

  @override
  void didUpdateWidget(covariant _PowerLimitSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reading.value != widget.reading.value ||
        (oldWidget.isApplying && !widget.isApplying)) {
      _value = _clampedValue(widget.reading);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spec = widget.reading.spec;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(spec.label)),
            Text('${_value.round()} ${spec.unit}', style: monoStatValueStyle),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: widget.accent,
            thumbColor: widget.accent,
            overlayColor: widget.accent.withValues(alpha: 0.12),
            inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.1),
          ),
          child: Slider(
            key: ValueKey('power-limit-slider-${spec.id}'),
            value: _value,
            min: spec.min.toDouble(),
            max: spec.max.toDouble(),
            divisions: spec.max - spec.min,
            label: '${_value.round()} ${spec.unit}',
            onChanged: widget.isApplying
                ? null
                : (value) => setState(() => _value = value),
            onChangeEnd: widget.isApplying
                ? null
                : (value) async {
                    final accepted = await widget.onChanged(value.round());
                    if (!accepted && mounted) {
                      setState(() => _value = _clampedValue(widget.reading));
                    }
                  },
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

  double _clampedValue(PowerLimitReading reading) =>
      reading.value.clamp(reading.spec.min, reading.spec.max).toDouble();
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
