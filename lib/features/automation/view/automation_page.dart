import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../../../core/widgets/surface_card.dart';
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

    final contextTriggers = [
      if (state.config.triggerOnProfileChange) 'profile changes',
      if (state.config.triggerOnPowerSourceChange) 'power source changes',
    ];

    return AppPageBody(
      errorMessage: state.errorMessage,
      children: [
        // The runner is infrastructure for the rules, not another rule.
        _AutomationCard(
          icon: YaruIcons.power,
          title: 'Automation runner',
          children: [
            AppSwitchTile(
              value: state.config.runnerEnabled,
              onChanged: (enabled) => ref
                  .read(automationBlocProvider.bloc)
                  .add(AutomationRunnerToggled(enabled)),
              title: 'Run automation rules',
              subtitle: state.config.runnerEnabled
                  ? 'Running every ${state.config.pollIntervalSeconds}s'
                  : 'Stopped',
            ),
            YaruListTile(
              title: Text(
                'Poll interval: ${state.config.pollIntervalSeconds} seconds',
              ),
              subtitle: Slider(
                value: state.config.pollIntervalSeconds.toDouble(),
                min: 2,
                max: 300,
                divisions: 298,
                label: '${state.config.pollIntervalSeconds}',
                onChanged: (value) {
                  ref
                      .read(automationBlocProvider.bloc)
                      .add(AutomationPollIntervalUpdated(value.round()));
                },
              ),
            ),
            const PrivilegedActionNotice(
              message: 'Run actions may require admin privileges',
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: state.isExecuting
                  ? null
                  : () async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Run automation now',
                        message:
                            'This can execute privileged hardware actions (fan presets and conservation updates) and may prompt for authentication.',
                        confirmLabel: 'Run now',
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
              label: const Text('Run now'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _AutomationCard(
          icon: YaruIcons.settings,
          title: 'Rules',
          children: [
            Text(
              'Choose what changes trigger actions, then enable the actions '
              'you want the runner to apply.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            YaruExpandable(
              isExpanded: false,
              expandButtonPosition: YaruExpandableButtonPosition.end,
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contextTriggers.isEmpty
                        ? 'No context triggers enabled'
                        : 'When ${contextTriggers.join(' or ')}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Fan preset ${state.config.applyFanPresetOnContextChange ? 'enabled' : 'disabled'} · '
                    'Rapid charging ${state.config.applyRapidChargingPolicy ? 'enabled' : 'disabled'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'WHEN',
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
                          .add(
                            AutomationTriggerOnProfileChangeToggled(enabled),
                          );
                    },
                    title: 'Trigger on profile change',
                    subtitle: 'quiet/balanced/performance transitions',
                  ),
                  AppSwitchTile(
                    value: state.config.triggerOnPowerSourceChange,
                    onChanged: (enabled) {
                      ref
                          .read(automationBlocProvider.bloc)
                          .add(
                            AutomationTriggerOnPowerSourceChangeToggled(
                              enabled,
                            ),
                          );
                    },
                    title: 'Trigger on power-source change',
                    subtitle: 'AC plugged/unplugged',
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'THEN',
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
                    title: 'Apply fan preset on power-context change',
                    subtitle: 'When profile or AC power changes',
                  ),
                  AppSwitchTile(
                    value: state.config.applyRapidChargingPolicy,
                    onChanged: (enabled) {
                      ref
                          .read(automationBlocProvider.bloc)
                          .add(AutomationRapidChargingPolicyToggled(enabled));
                    },
                    title: 'Apply rapid-charging policy',
                    subtitle:
                        'When an enabled profile or power-source trigger changes',
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
                            title: 'Enable rapid charging on AC',
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
                            title: 'Enable rapid charging on battery',
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _AutomationCard(
          icon: YaruIcons.battery,
          title: 'Battery conservation',
          children: [
            AppSwitchTile(
              value: state.config.applyCustomConservation,
              onChanged: (enabled) {
                ref
                    .read(automationBlocProvider.bloc)
                    .add(AutomationConservationRuleToggled(enabled));
              },
              title: 'Apply custom conservation policy',
              subtitle: 'Apply on every automation cycle',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 180,
                  child: _LimitField(
                    label: 'Conservation lower limit (%)',
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
                ),
                SizedBox(
                  width: 180,
                  child: _LimitField(
                    label: 'Conservation upper limit (%)',
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
                ),
              ],
            ),
            if (!state.config.hasValidConservationRange)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Invalid limits: lower limit must be <= upper limit.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        _AutomationCard(
          icon: YaruIcons.gears,
          title: 'Run command…',
          children: [
            YaruExpandable(
              isExpanded: false,
              expandButtonPosition: YaruExpandableButtonPosition.end,
              header: Text(
                !state.config.runExternalCommand
                    ? 'Disabled · ${state.config.externalCommandOnContextChange ? 'on context changes' : 'every cycle'}'
                    : state.config.externalCommandOnContextChange
                    ? 'Run command on context changes'
                    : 'Run command every cycle',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSwitchTile(
                    value: state.config.runExternalCommand,
                    onChanged: (enabled) {
                      ref
                          .read(automationBlocProvider.bloc)
                          .add(AutomationExternalCommandRuleToggled(enabled));
                    },
                    title: 'Enable command action',
                    subtitle: 'Execute a shell command as your user account',
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
                                  .add(
                                    AutomationExternalCommandUpdated(command),
                                  );
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
                            title: 'Only on context change',
                            subtitle:
                                state.config.externalCommandOnContextChange
                                ? 'Runs when profile or power source changes'
                                : 'Runs every automation cycle',
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _AutomationCard(
          icon: YaruIcons.information,
          title: 'Recent run',
          children: [
            _StatusLine(
              label: 'Last run',
              value: state.lastRunAt?.toLocal().toString() ?? 'Never',
            ),
            _StatusLine(
              label: 'Result',
              value: state.lastRunSummary ?? 'No run recorded',
            ),
            _StatusLine(
              label: 'Profile',
              value: state.currentSnapshot?.platformProfile ?? 'Unknown',
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
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Wrap(
      spacing: 6,
      children: [
        Text('$label:', style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

class _AutomationCard extends StatelessWidget {
  const _AutomationCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
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
      decoration: const InputDecoration(
        labelText: 'Shell command',
        hintText: 'e.g. notify-send "Automation ran"',
      ),
      onSubmitted: (value) => widget.onSubmitted(value.trim()),
    );
  }
}
