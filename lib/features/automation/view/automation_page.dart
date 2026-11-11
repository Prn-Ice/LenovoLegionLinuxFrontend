import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/surface_card.dart';
import '../../lighting/bloc/rgb_lighting_event.dart';
import '../../lighting/providers/lighting_provider.dart';
import '../../navigation/bloc/navigation_event.dart';
import '../../navigation/models/app_section.dart';
import '../../navigation/providers/navigation_provider.dart';
import '../bloc/automation_event.dart';
import '../models/automation_config.dart';
import '../providers/automation_provider.dart';
import '../providers/automation_runtime_provider.dart';

class AutomationPage extends ConsumerWidget {
  const AutomationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(automationBlocProvider);
    final lighting = ref.watch(rgbLightingBlocProvider);
    final assignment = ref.watch(activeKeyboardAssignmentProvider);
    final theme = Theme.of(context);

    return AppPageBody(
      errorMessage: state.errorMessage ?? lighting.visibleErrorMessage,
      onErrorDismissed: (error) =>
          ref.read(rgbLightingBlocProvider.bloc).add(RgbErrorDismissed(error)),
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Keyboard profiles by power mode',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose how your keyboard looks in each power mode. Changes from Fn+Q, the CLI, desktop settings, or this app use the same assignments.',
              ),
              const SizedBox(height: 8),
              Text(
                'Applies when the app opens and when the mode changes. Keep the app open for automatic switching.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    assignment.mode == null
                        ? 'Current mode unavailable'
                        : 'Current mode: ${assignment.mode!.label}',
                    style: theme.textTheme.titleSmall,
                  ),
                  if (assignment.profile != null)
                    OutlinedButton(
                      onPressed: lighting.isApplying || lighting.isLoading
                          ? null
                          : () => ref
                                .read(rgbLightingBlocProvider.bloc)
                                .add(RgbProfileLoaded(assignment.profile!)),
                      child: const Text('Apply current profile'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.isLoading && !state.hasLoaded)
                const Center(child: YaruCircularProgressIndicator())
              else if (!state.hasLoaded)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: () => ref
                        .read(automationBlocProvider.bloc)
                        .add(const AutomationStarted()),
                    child: const Text('Retry loading assignments'),
                  ),
                )
              else ...[
                for (final mode in KeyboardPowerMode.values) ...[
                  if (mode != KeyboardPowerMode.quiet)
                    const Divider(height: 32),
                  _ProfileAssignment(
                    mode: mode,
                    profile: state.config.profiles[mode],
                    names: lighting.profileNames,
                    enabled: !state.isSaving,
                    onChanged: (name) => ref
                        .read(automationBlocProvider.bloc)
                        .add(KeyboardProfileAssigned(mode, name)),
                  ),
                ],
              ],
              const SizedBox(height: 20),
              Text(
                lighting.profileNames.isEmpty
                    ? 'Save a named profile in Lighting to make it available here. Until then, your keyboard stays unchanged.'
                    : 'Leave unchanged keeps your current lighting. Selecting a profile for the current mode applies it immediately.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(YaruIcons.keyboard, size: 18),
                  label: const Text('Manage lighting profiles'),
                  onPressed: () => ref
                      .read(navigationBlocProvider.bloc)
                      .add(
                        const NavigationSectionSelected(AppSection.lighting),
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileAssignment extends StatelessWidget {
  const _ProfileAssignment({
    required this.mode,
    required this.profile,
    required this.names,
    required this.enabled,
    required this.onChanged,
  });
  final KeyboardPowerMode mode;
  final String? profile;
  final List<String> names;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final missing = profile != null && !names.contains(profile);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(mode.label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey((mode, profile)),
          initialValue: profile,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: '${mode.label} keyboard profile',
          ),
          hint: const Text('Leave unchanged'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Leave unchanged')),
            for (final name in names)
              DropdownMenuItem(
                value: name,
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            if (missing)
              DropdownMenuItem(
                value: profile,
                child: Text(
                  '$profile (missing)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: enabled ? onChanged : null,
        ),
        if (missing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'This profile was deleted. Choose another profile or Leave unchanged.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
