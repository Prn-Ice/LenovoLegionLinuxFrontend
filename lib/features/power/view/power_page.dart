import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/power_bloc.dart';
import '../bloc/power_event.dart';
import '../models/power_limit.dart';
import '../models/power_mode.dart';
import '../providers/power_provider.dart';

class PowerPage extends ConsumerWidget {
  const PowerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(powerBlocProvider);
    final bloc = ref.read(powerBlocProvider.bloc);
    final textTheme = Theme.of(context).textTheme;

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Power', style: textTheme.headlineMedium),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current Mode', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  state.currentMode?.label ?? 'Unavailable',
                  style: textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                if (state.errorMessage != null) ...[
                  Text(
                    state.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (state.noticeMessage != null) ...[
                  Text(
                    state.noticeMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton.icon(
                  onPressed: state.isLoading || state.isApplying
                      ? null
                      : () => bloc.add(const PowerRefreshRequested()),
                  icon: state.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('Refresh'),
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
                Text('Select Mode', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                const PrivilegedActionNotice(),
                const SizedBox(height: 8),
                if (state.availableModes.isEmpty)
                  const Text('No power mode options available on this system.'),
                if (state.availableModes.isNotEmpty)
                  RadioGroup<String>(
                    groupValue: state.currentMode?.value,
                    onChanged: (value) async {
                      if (state.isApplying || value == null) {
                        return;
                      }

                      final mode = state.availableModes.firstWhere(
                        (entry) => entry.value == value,
                        orElse: () => PowerMode(value),
                      );

                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Set power mode',
                        message:
                            'Changing power mode uses a privileged command and may prompt for authentication.',
                        confirmLabel: 'Set mode',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }

                      _setMode(bloc, mode);
                    },
                    child: Column(
                      children: state.availableModes
                          .map(
                            (mode) => RadioListTile<String>(
                              value: mode.value,
                              title: Text(mode.label),
                              subtitle: Text(mode.value),
                            ),
                          )
                          .toList(growable: false),
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
                Text('Power Limits (Advanced)', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                const PrivilegedActionNotice(),
                const SizedBox(height: 8),
                const Text(
                  'These limits are hardware-dependent and may only apply in custom/performance profiles.',
                ),
                if (state.powerLimits.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'No power limit controls are available on this system.',
                    ),
                  ),
                ...state.powerLimits.map(
                  (reading) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(reading.spec.label),
                    subtitle: Text(
                      'Current: ${reading.value} | Range: ${reading.spec.min}-${reading.spec.max}',
                    ),
                    trailing: OutlinedButton(
                      onPressed: state.isApplying
                          ? null
                          : () => _promptAndSetLimit(
                              context,
                              bloc,
                              reading.spec,
                              reading.value,
                            ),
                      child: const Text('Set'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _setMode(PowerBloc bloc, PowerMode mode) {
    bloc.add(PowerModeSetRequested(mode));
  }

  Future<void> _promptAndSetLimit(
    BuildContext context,
    PowerBloc bloc,
    PowerLimitSpec limit,
    int currentValue,
  ) async {
    final controller = TextEditingController(text: '$currentValue');

    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(limit.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Allowed range: ${limit.min}-${limit.max}'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Value'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed == null) {
                Navigator.of(dialogContext).pop();
                return;
              }
              Navigator.of(dialogContext).pop(parsed);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (result == null) {
      return;
    }

    if (result < limit.min || result > limit.max) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${limit.label} must be between ${limit.min} and ${limit.max}.',
            ),
          ),
        );
      }
      return;
    }

    if (!context.mounted) {
      return;
    }

    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Apply power limit',
      message:
          'Setting ${limit.label} uses a privileged command and may prompt for authentication.',
      confirmLabel: 'Apply limit',
    );
    if (!context.mounted || !confirmed) {
      return;
    }

    bloc.add(PowerLimitSetRequested(limit: limit, value: result));
  }
}
