import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/automation_event.dart';
import '../providers/automation_provider.dart';

class AutomationPage extends ConsumerWidget {
  const AutomationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(automationBlocProvider);
    final bloc = ref.read(automationBlocProvider.bloc);
    final textTheme = Theme.of(context).textTheme;

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Automation', style: textTheme.headlineMedium),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Runner', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: state.config.runnerEnabled,
                  onChanged: (enabled) =>
                      bloc.add(AutomationRunnerToggled(enabled)),
                  title: const Text('Enable automation runner'),
                  subtitle: Text(
                    state.config.runnerEnabled
                        ? 'Running every ${state.config.pollIntervalSeconds}s'
                        : 'Stopped',
                  ),
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
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rules', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: state.config.applyFanPresetOnContextChange,
                  onChanged: (enabled) {
                    bloc.add(AutomationFanPresetRuleToggled(enabled));
                  },
                  title: const Text('Apply fan preset on power-context change'),
                  subtitle: const Text('Trigger: AC/profile changes'),
                ),
                SwitchListTile.adaptive(
                  value: state.config.applyCustomConservation,
                  onChanged: (enabled) {
                    bloc.add(AutomationConservationRuleToggled(enabled));
                  },
                  title: const Text('Apply custom conservation policy'),
                  subtitle: const Text('Trigger: each automation cycle'),
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Status', style: textTheme.titleLarge),
                const SizedBox(height: 8),
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
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
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
