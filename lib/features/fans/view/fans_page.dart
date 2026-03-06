import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/fans_event.dart';
import '../providers/fans_provider.dart';

class FansPage extends ConsumerWidget {
  const FansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fansBlocProvider);
    final bloc = ref.read(fansBlocProvider.bloc);

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    return AppPageBody(
      title: 'Fans',
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        AppSectionCard(
          title: 'Current Context',
          children: [
            Text('Profile: ${state.platformProfile ?? 'Unknown'}'),
            Text(
              'Power source: ${state.onPowerSupply == null ? 'Unknown' : (state.onPowerSupply! ? 'AC' : 'Battery')}',
            ),
            Text(
              'Recommended preset: ${state.recommendedPreset ?? 'Unavailable'}',
            ),
            const SizedBox(height: 12),
            const PrivilegedActionNotice(),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: state.isApplying
                  ? null
                  : () async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Apply context preset',
                        message:
                            'Applying a fan preset writes hardware controls and may prompt for authentication.',
                        confirmLabel: 'Apply preset',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(const FansApplyCurrentPresetRequested());
                    },
              icon: state.isApplying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: YaruCircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.tune),
              label: const Text('Apply context preset'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppSectionCard(
          title: 'Manual Preset',
          children: [
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
                  : () async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Apply selected fan preset',
                        message:
                            'Applying fan presets requires privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply preset',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(const FansApplySelectedPresetRequested());
                    },
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('Apply selected preset'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppSectionCard(
          title: 'Fan Controls',
          children: [
            const PrivilegedActionNotice(),
            const SizedBox(height: 8),
            AppSwitchTile(
              value: state.miniFanCurveEnabled ?? false,
              onChanged:
                  (state.miniFanCurveEnabled != null && !state.isApplying)
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Set mini fan curve',
                        message:
                            'This action uses privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(MiniFanCurveSetRequested(enabled));
                    }
                  : null,
              title: 'Mini fan curve',
              subtitle: boolEnabledLabel(state.miniFanCurveEnabled),
            ),
            AppSwitchTile(
              value: state.lockFanControllerEnabled ?? false,
              onChanged:
                  (state.lockFanControllerEnabled != null && !state.isApplying)
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Set lock fan controller',
                        message:
                            'This action uses privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(LockFanControllerSetRequested(enabled));
                    }
                  : null,
              title: 'Lock fan controller',
              subtitle: boolEnabledLabel(state.lockFanControllerEnabled),
            ),
            AppSwitchTile(
              value: state.maximumFanSpeedEnabled ?? false,
              onChanged:
                  (state.maximumFanSpeedEnabled != null && !state.isApplying)
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Set maximum fan speed',
                        message:
                            'This action uses privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(MaximumFanSpeedSetRequested(enabled));
                    }
                  : null,
              title: 'Maximum fan speed',
              subtitle: boolEnabledLabel(state.maximumFanSpeedEnabled),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppRefreshButton(
          isBusy: state.isLoading,
          onPressed: state.isApplying
              ? null
              : () => bloc.add(const FansRefreshRequested()),
        ),
      ],
    );
  }
}
