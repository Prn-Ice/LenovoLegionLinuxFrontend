import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bloc/fans_event.dart';
import '../providers/fans_provider.dart';

class FansPage extends ConsumerWidget {
  const FansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fansBlocProvider);
    final bloc = ref.read(fansBlocProvider.bloc);
    final textTheme = Theme.of(context).textTheme;

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Fans', style: textTheme.headlineMedium),
        const SizedBox(height: 16),
        if (state.errorMessage != null) ...[
          Text(
            state.errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
        ],
        if (state.noticeMessage != null) ...[
          Text(
            state.noticeMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 8),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current Context', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('Profile: ${state.platformProfile ?? 'Unknown'}'),
                Text(
                  'Power source: ${state.onPowerSupply == null ? 'Unknown' : (state.onPowerSupply! ? 'AC' : 'Battery')}',
                ),
                Text(
                  'Recommended preset: ${state.recommendedPreset ?? 'Unavailable'}',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: state.isApplying
                      ? null
                      : () => bloc.add(const FansApplyCurrentPresetRequested()),
                  icon: state.isApplying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.tune),
                  label: const Text('Apply context preset'),
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
                Text('Manual Preset', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: state.selectedPreset,
                  items: state.availablePresets
                      .map(
                        (preset) => DropdownMenuItem<String>(
                          value: preset,
                          child: Text(preset),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: state.isApplying
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          bloc.add(FansPresetSelectionChanged(value));
                        },
                  decoration: const InputDecoration(labelText: 'Fan preset'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: state.isApplying
                      ? null
                      : () =>
                            bloc.add(const FansApplySelectedPresetRequested()),
                  icon: const Icon(Icons.playlist_add_check),
                  label: const Text('Apply selected preset'),
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
                Text('Fan Controls', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: state.miniFanCurveEnabled ?? false,
                  onChanged:
                      (state.miniFanCurveEnabled != null && !state.isApplying)
                      ? (enabled) => bloc.add(MiniFanCurveSetRequested(enabled))
                      : null,
                  title: const Text('Mini fan curve'),
                  subtitle: Text(_boolStatus(state.miniFanCurveEnabled)),
                ),
                SwitchListTile.adaptive(
                  value: state.lockFanControllerEnabled ?? false,
                  onChanged:
                      (state.lockFanControllerEnabled != null &&
                          !state.isApplying)
                      ? (enabled) =>
                            bloc.add(LockFanControllerSetRequested(enabled))
                      : null,
                  title: const Text('Lock fan controller'),
                  subtitle: Text(_boolStatus(state.lockFanControllerEnabled)),
                ),
                SwitchListTile.adaptive(
                  value: state.maximumFanSpeedEnabled ?? false,
                  onChanged:
                      (state.maximumFanSpeedEnabled != null &&
                          !state.isApplying)
                      ? (enabled) =>
                            bloc.add(MaximumFanSpeedSetRequested(enabled))
                      : null,
                  title: const Text('Maximum fan speed'),
                  subtitle: Text(_boolStatus(state.maximumFanSpeedEnabled)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: state.isLoading || state.isApplying
              ? null
              : () => bloc.add(const FansRefreshRequested()),
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
    );
  }

  String _boolStatus(bool? value) {
    if (value == null) {
      return 'Unavailable on this device';
    }
    return value ? 'Enabled' : 'Disabled';
  }
}
