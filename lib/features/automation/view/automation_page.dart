import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/metric_text.dart';
import '../../../core/widgets/responsive_card_grid.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../../../core/widgets/surface_card.dart';
import '../../dashboard/widgets/mode_hero.dart' show modeLabel;
import '../bloc/automation_event.dart';
import '../providers/automation_provider.dart';

class AutomationPage extends ConsumerWidget {
  const AutomationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(automationBlocProvider);

    if (state.isLoading) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    final automaticChecks = _AutomationCard(
      icon: YaruIcons.media_play,
      title: 'Apply your choices',
      description:
          'Enable automatic checks, or apply your enabled actions once.',
      children: [
        AppSwitchTile(
          value: state.config.runnerEnabled,
          onChanged: (enabled) => ref
              .read(automationBlocProvider.bloc)
              .add(AutomationRunnerToggled(enabled)),
          title: 'Enable automation',
          subtitle: state.config.runnerEnabled
              ? 'Checking every ${state.config.pollIntervalSeconds} seconds. '
                    'Automation stops when this app closes.'
              : 'Off — your choices are saved, but automatic changes are paused.',
        ),
        const Divider(height: 24),
        Text(
          'Apply now runs all enabled actions once, even when automation is off. '
          'It does not wait for a power change.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              onPressed: state.isExecuting
                  ? null
                  : () async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Apply enabled actions now',
                        message:
                            'Apply the enabled fan and charging settings for the current power mode and power source. '
                            'An enabled shell command will also run. You may be asked to authenticate.',
                        confirmLabel: 'Apply now',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      ref
                          .read(automationBlocProvider.bloc)
                          .add(const AutomationRunNowRequested());
                    },
              icon: state.isExecuting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: YaruCircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(YaruIcons.media_play),
              label: const Text('Apply now'),
            ),
            const PrivilegedActionNotice(
              compact: true,
              message: 'Run actions may require admin privileges',
            ),
          ],
        ),
      ],
    );

    final powerChanges = _AutomationCard(
      icon: YaruIcons.thunderbolt,
      title: 'When power changes',
      description: 'Choose which changes to watch and what Legion should do.',
      children: [
        ResponsiveCardGrid(
          minCardWidth: 320,
          spacing: 24,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'When this happens',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                AppSwitchTile(
                  value: state.config.triggerOnProfileChange,
                  onChanged: (enabled) {
                    ref
                        .read(automationBlocProvider.bloc)
                        .add(AutomationTriggerOnProfileChangeToggled(enabled));
                  },
                  title: 'Power mode changes',
                  subtitle:
                      'Switching between Quiet, Balanced, Performance or Custom',
                ),
                AppSwitchTile(
                  value: state.config.triggerOnPowerSourceChange,
                  onChanged: (enabled) {
                    ref
                        .read(automationBlocProvider.bloc)
                        .add(
                          AutomationTriggerOnPowerSourceChangeToggled(enabled),
                        );
                  },
                  title: 'Charger connected or disconnected',
                  subtitle: 'Switching between AC power and battery',
                ),
                if (!state.config.triggerOnProfileChange &&
                    !state.config.triggerOnPowerSourceChange)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Choose at least one change to apply these actions automatically.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Do this',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                AppSwitchTile(
                  value: state.config.applyFanPresetOnContextChange,
                  onChanged: (enabled) {
                    ref
                        .read(automationBlocProvider.bloc)
                        .add(AutomationFanPresetRuleToggled(enabled));
                  },
                  title: 'Apply matching fan preset',
                  subtitle:
                      'Use the saved fan preset for the current power mode and AC or battery power.',
                ),
                AppSwitchTile(
                  value: state.config.applyRapidChargingPolicy,
                  onChanged: (enabled) {
                    ref
                        .read(automationBlocProvider.bloc)
                        .add(AutomationRapidChargingPolicyToggled(enabled));
                  },
                  title: 'Set rapid charging',
                  subtitle:
                      'Turn rapid charging on or off for each power source.',
                ),
                if (state.config.applyRapidChargingPolicy)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, right: 12),
                    child: Column(
                      children: [
                        AppSwitchTile(
                          contentPadding: EdgeInsets.zero,
                          value: state.config.rapidChargingOnAc,
                          onChanged: (enabled) {
                            ref
                                .read(automationBlocProvider.bloc)
                                .add(
                                  AutomationRapidChargingTargetsUpdated(
                                    onAc: enabled,
                                    onBattery:
                                        state.config.rapidChargingOnBattery,
                                  ),
                                );
                          },
                          title: 'Rapid charging on AC power',
                        ),
                        AppSwitchTile(
                          contentPadding: EdgeInsets.zero,
                          value: state.config.rapidChargingOnBattery,
                          onChanged: (enabled) {
                            ref
                                .read(automationBlocProvider.bloc)
                                .add(
                                  AutomationRapidChargingTargetsUpdated(
                                    onAc: state.config.rapidChargingOnAc,
                                    onBattery: enabled,
                                  ),
                                );
                          },
                          title: 'Rapid charging on battery power',
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
    final batteryLimits = _AutomationCard(
      icon: YaruIcons.battery,
      title: 'Battery charge limits',
      description:
          'Keep applying a battery conservation range, independently of power changes.',
      children: [
        AppSwitchTile(
          value: state.config.applyCustomConservation,
          onChanged: (enabled) {
            ref
                .read(automationBlocProvider.bloc)
                .add(AutomationConservationRuleToggled(enabled));
          },
          title: 'Maintain charge limits',
          subtitle: state.config.applyCustomConservation
              ? 'Apply the ${state.config.conservationLowerLimit}–${state.config.conservationUpperLimit}% range at every automatic check.'
              : 'Off — automation will not apply battery charge limits.',
        ),
        if (state.config.applyCustomConservation) ...[
          const SizedBox(height: 8),
          ResponsiveCardGrid(
            minCardWidth: 210,
            children: [
              _LimitField(
                label: 'Lower limit (%)',
                initialValue: state.config.conservationLowerLimit,
                onSubmitted: (value) => ref
                    .read(automationBlocProvider.bloc)
                    .add(
                      AutomationConservationLimitsUpdated(
                        lower: value,
                        upper: state.config.conservationUpperLimit,
                      ),
                    ),
              ),
              _LimitField(
                label: 'Upper limit (%)',
                initialValue: state.config.conservationUpperLimit,
                onSubmitted: (value) => ref
                    .read(automationBlocProvider.bloc)
                    .add(
                      AutomationConservationLimitsUpdated(
                        lower: state.config.conservationLowerLimit,
                        upper: value,
                      ),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Press Enter in each field to save its limit.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!state.config.hasValidConservationRange)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'The lower limit must be less than or equal to the upper limit.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ],
    );

    final advanced = _AutomationCard(
      icon: YaruIcons.terminal,
      title: 'Advanced',
      expandable: true,
      description: 'Check frequency and an optional shell command.',
      children: [
        Text(
          'Check every ${state.config.pollIntervalSeconds} seconds',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'How often Legion checks for power changes and reapplies enabled charge limits.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Slider(
            value: state.config.pollIntervalSeconds.toDouble(),
            min: 2,
            max: 300,
            divisions: 298,
            label: '${state.config.pollIntervalSeconds} seconds',
            semanticFormatterCallback: (value) => '${value.round()} seconds',
            onChanged: (value) => ref
                .read(automationBlocProvider.bloc)
                .add(AutomationPollIntervalUpdated(value.round())),
          ),
        ),
        const Divider(height: 24),
        AppSwitchTile(
          value: state.config.runExternalCommand,
          onChanged: (enabled) {
            ref
                .read(automationBlocProvider.bloc)
                .add(AutomationExternalCommandRuleToggled(enabled));
          },
          title: 'Run a shell command',
          subtitle: 'Optional: run your own script as your user account.',
        ),
        if (state.config.runExternalCommand) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(YaruIcons.warning, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Runs as your user account, not as root. '
                        'Avoid commands that require admin privileges.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _CommandField(
                  initialValue: state.config.externalCommand,
                  onSubmitted: (command) {
                    ref
                        .read(automationBlocProvider.bloc)
                        .add(AutomationExternalCommandUpdated(command));
                  },
                ),
                const SizedBox(height: 8),
                AppSwitchTile(
                  contentPadding: EdgeInsets.zero,
                  value: state.config.externalCommandOnContextChange,
                  onChanged: (onContextChange) {
                    ref
                        .read(automationBlocProvider.bloc)
                        .add(
                          AutomationExternalCommandTriggerUpdated(
                            onContextChange,
                          ),
                        );
                  },
                  title: 'Only after a selected power change',
                  subtitle: state.config.externalCommandOnContextChange
                      ? 'Uses the changes selected under When power changes.'
                      : 'Runs at every automatic check.',
                ),
              ],
            ),
          ),
        ],
      ],
    );

    final activity = _AutomationCard(
      icon: YaruIcons.history,
      title: 'Activity',
      expandable: true,
      description: state.lastRunAt == null
          ? 'No checks yet. Enable automation or use Apply now after choosing your actions.'
          : state.lastRunSummary ?? 'Last check did not complete.',
      children: [
        _StatusLine(
          label: 'Last check',
          value: state.lastRunAt == null
              ? 'Not yet'
              : _formatRunTime(context, state.lastRunAt!),
        ),
        _StatusLine(
          label: 'Result',
          value: state.lastRunSummary ?? 'No run recorded',
        ),
        _StatusLine(
          label: 'Power mode',
          value: modeLabel(state.currentSnapshot?.platformProfile),
        ),
        _StatusLine(
          label: 'Power source',
          value: state.currentSnapshot?.onPowerSupply == null
              ? 'Unknown'
              : state.currentSnapshot!.onPowerSupply!
              ? 'AC'
              : 'Battery',
        ),
      ],
    );

    return AppPageBody(
      errorMessage: state.errorMessage,
      children: [
        Text(
          'Let Legion adjust fan and charging settings for you.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Choose what should happen below, then enable automation. '
          'For example, reapply the matching fan preset when you unplug the charger.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        powerChanges,
        const SizedBox(height: 16),
        batteryLimits,
        const SizedBox(height: 16),
        automaticChecks,
        const SizedBox(height: 16),
        advanced,
        const SizedBox(height: 16),
        activity,
      ],
    );
  }
}

String _formatRunTime(BuildContext context, DateTime time) {
  final local = time.toLocal();
  final labels = MaterialLocalizations.of(context);
  return '${labels.formatCompactDate(local)} · '
      '${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.56),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(
            value,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

class _AutomationCard extends StatelessWidget {
  const _AutomationCard({
    required this.icon,
    required this.title,
    this.description,
    this.expandable = false,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String? description;
  final bool expandable;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              if (description != null) ...[
                const SizedBox(height: 4),
                Text(
                  description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.56),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
    return SurfaceCard(
      child: expandable
          ? YaruExpandable(
              isExpanded: false,
              expandIconSemanticLabel: '$title details',
              expandButtonPosition: YaruExpandableButtonPosition.end,
              header: header,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: body,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [header, const SizedBox(height: 16), body],
            ),
    );
  }
}

class _LimitField extends StatefulWidget {
  const _LimitField({
    required this.label,
    required this.initialValue,
    required this.onSubmitted,
  });

  final String label;
  final int initialValue;
  final ValueChanged<int> onSubmitted;

  @override
  State<_LimitField> createState() => _LimitFieldState();
}

class _LimitFieldState extends State<_LimitField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialValue}');
  }

  @override
  void didUpdateWidget(covariant _LimitField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        _controller.text != '${widget.initialValue}') {
      _controller.text = '${widget.initialValue}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: widget.label),
      onSubmitted: (value) {
        final parsed = int.tryParse(value.trim());
        if (parsed == null) {
          return;
        }
        widget.onSubmitted(parsed.clamp(0, 100));
      },
    );
  }
}

class _CommandField extends StatefulWidget {
  const _CommandField({required this.initialValue, required this.onSubmitted});

  final String initialValue;
  final ValueChanged<String> onSubmitted;

  @override
  State<_CommandField> createState() => _CommandFieldState();
}

class _CommandFieldState extends State<_CommandField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _CommandField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        _controller.text != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      style: monoFactStyle(Theme.of(context).colorScheme),
      decoration: const InputDecoration(
        labelText: 'Shell command',
        hintText: 'e.g. notify-send "Automation ran"',
      ),
      onSubmitted: (value) => widget.onSubmitted(value.trim()),
    );
  }
}
