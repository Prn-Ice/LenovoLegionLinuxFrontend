import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/automation_event.dart';
import '../providers/automation_provider.dart';

class AutomationPage extends ConsumerWidget {
  const AutomationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(automationBlocProvider);
    final bloc = ref.read(automationBlocProvider.bloc);

    if (state.isLoading) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    return AppPageBody(
      title: 'Automation',
      errorMessage: state.errorMessage,
      children: [
        AppSectionCard(
          title: 'Runner',
          children: [
            AppSwitchTile(
              value: state.config.runnerEnabled,
              onChanged: (enabled) =>
                  bloc.add(AutomationRunnerToggled(enabled)),
              title: 'Enable automation runner',
              subtitle: state.config.runnerEnabled
                  ? 'Running every ${state.config.pollIntervalSeconds}s'
                  : 'Stopped',
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Poll interval (seconds)'),
              subtitle: Slider(
                value: state.config.pollIntervalSeconds.toDouble(),
                min: 2,
                max: 60,
                divisions: 58,
                label: '${state.config.pollIntervalSeconds}',
                onChanged: (value) {
                  bloc.add(AutomationPollIntervalUpdated(value.round()));
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
                      bloc.add(const AutomationRunNowRequested());
                    },
              icon: state.isExecuting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: const Text('Run now'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppSectionCard(
          title: 'Rules',
          children: [
            Text(
              'Trigger model',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            AppSwitchTile(
              value: state.config.triggerOnProfileChange,
              onChanged: (enabled) {
                bloc.add(AutomationTriggerOnProfileChangeToggled(enabled));
              },
              title: 'Trigger on profile change',
              subtitle: 'quiet/balanced/performance transitions',
            ),
            AppSwitchTile(
              value: state.config.triggerOnPowerSourceChange,
              onChanged: (enabled) {
                bloc.add(AutomationTriggerOnPowerSourceChangeToggled(enabled));
              },
              title: 'Trigger on power-source change',
              subtitle: 'AC plugged/unplugged',
            ),
            const SizedBox(height: 8),
            Text(
              'Action chain',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            AppSwitchTile(
              value: state.config.applyFanPresetOnContextChange,
              onChanged: (enabled) {
                bloc.add(AutomationFanPresetRuleToggled(enabled));
              },
              title: 'Apply fan preset on power-context change',
              subtitle: 'Trigger: AC/profile changes',
            ),
            AppSwitchTile(
              value: state.config.applyCustomConservation,
              onChanged: (enabled) {
                bloc.add(AutomationConservationRuleToggled(enabled));
              },
              title: 'Apply custom conservation policy',
              subtitle: 'Trigger: each automation cycle',
            ),
            AppSwitchTile(
              value: state.config.applyRapidChargingPolicy,
              onChanged: (enabled) {
                bloc.add(AutomationRapidChargingPolicyToggled(enabled));
              },
              title: 'Apply rapid-charging policy',
              subtitle: 'Trigger: selected context changes',
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
                        bloc.add(
                          AutomationRapidChargingTargetsUpdated(
                            onAc: enabled,
                            onBattery: state.config.rapidChargingOnBattery,
                          ),
                        );
                      },
                      title: 'Enable rapid charging on AC',
                    ),
                    AppSwitchTile(
                      contentPadding: EdgeInsets.zero,
                      value: state.config.rapidChargingOnBattery,
                      onChanged: (enabled) {
                        bloc.add(
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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _LimitField(
                    label: 'Lower %',
                    initialValue: state.config.conservationLowerLimit,
                    onSubmitted: (value) {
                      bloc.add(
                        AutomationConservationLimitsUpdated(
                          lower: value,
                          upper: state.config.conservationUpperLimit,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LimitField(
                    label: 'Upper %',
                    initialValue: state.config.conservationUpperLimit,
                    onSubmitted: (value) {
                      bloc.add(
                        AutomationConservationLimitsUpdated(
                          lower: state.config.conservationLowerLimit,
                          upper: value,
                        ),
                      );
                    },
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
        AppSectionCard(
          title: 'Status',
          children: [
            Text(
              'Current profile: ${state.currentSnapshot?.platformProfile ?? 'Unknown'}',
            ),
            Text(
              'On power supply: ${state.currentSnapshot?.onPowerSupply?.toString() ?? 'Unknown'}',
            ),
            Text(
              'Last run: ${state.lastRunAt?.toLocal().toString() ?? 'Never'}',
            ),
            Text('Last result: ${state.lastRunSummary ?? 'None'}'),
          ],
        ),
      ],
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
