import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../../boot_logo/bloc/boot_logo_bloc.dart';
import '../../boot_logo/bloc/boot_logo_event.dart';
import '../../boot_logo/providers/boot_logo_provider.dart';
import '../bloc/settings_event.dart';
import '../models/service_control.dart';
import '../providers/settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsBlocProvider);
    final bloc = ref.read(settingsBlocProvider.bloc);
    final bootLogoState = ref.watch(bootLogoBlocProvider);
    final bootLogoBloc = ref.read(bootLogoBlocProvider.bloc);

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    final textTheme = Theme.of(context).textTheme;

    return AppPageBody(
      title: 'Settings',
      errorMessage: state.errorMessage,
      children: [
        AppControlCard(
          icon: Icons.palette_outlined,
          title: 'Appearance',
          children: [
            const SizedBox(height: 4),
            Text('Theme', style: textTheme.labelMedium),
            const SizedBox(height: 8),
            YaruChoiceChipBar(
              selectedFirst: false,
              labels: const [Text('System'), Text('Light'), Text('Dark')],
              isSelected: [
                state.themeMode == ThemeMode.system,
                state.themeMode == ThemeMode.light,
                state.themeMode == ThemeMode.dark,
              ],
              onSelected: (i) {
                const modes = [
                  ThemeMode.system,
                  ThemeMode.light,
                  ThemeMode.dark,
                ];
                bloc.add(ThemeModeChanged(modes[i]));
              },
            ),
            const SizedBox(height: 16),
            Text('Accent colour', style: textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: YaruVariant.accents.map((variant) {
                final selected = state.yaruVariant == variant;
                return InkWell(
                  onTap: () =>
                      bloc.add(YaruVariantChanged(selected ? null : variant)),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: variant.color,
                      border: selected
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 2.5,
                            )
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppControlCard(
          icon: Icons.settings_outlined,
          title: 'System Services',
          description:
              'Enable or disable Linux service dependencies used by Legion tooling.',
          children: [
            const PrivilegedActionNotice(),
            const SizedBox(height: 8),
            if (state.services.isEmpty)
              const Text('No service controls available.'),
            ...state.services.map(
              (service) => _ServiceTile(
                service: service,
                isBusy: state.isApplying,
                onChanged: (enabled) async {
                  final confirmed = await confirmPrivilegedAction(
                    context,
                    title: 'Update ${service.label}',
                    message:
                        'Changing Linux services uses privileged access and may prompt for authentication.',
                    confirmLabel: 'Apply',
                  );
                  if (!context.mounted || !confirmed) {
                    return;
                  }
                  bloc.add(
                    SettingsServiceToggled(
                      serviceId: service.id,
                      enabled: enabled,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppControlCard(
          icon: Icons.image_outlined,
          title: 'Boot Logo',
          description:
              'Set a custom logo shown during boot, or restore the stock Lenovo logo.',
          children: [
            if (bootLogoState.status == null)
              const YaruListTile(
                title: Text('Boot logo status unavailable'),
                subtitle: Text(
                  'This feature requires a supported Lenovo Legion model and readable EFI variables.',
                ),
              )
            else ...[
              _StatusRow(
                isCustomEnabled: bootLogoState.status!.isCustomEnabled,
                dimensionLabel: bootLogoState.status!.dimensionLabel,
              ),
              const SizedBox(height: 16),
              _FilePickerRow(
                selectedPath: bootLogoState.selectedImagePath,
                validationError: bootLogoState.validationError,
                isApplying: bootLogoState.isApplying,
                onPick: () => _pickFile(bootLogoBloc),
                onClear: () => bootLogoBloc.add(const BootLogoFileSelected('')),
              ),
              const SizedBox(height: 8),
              Text(
                bootLogoState.status!.hasDimensionConstraint
                    ? 'Required dimensions: ${bootLogoState.status!.dimensionLabel} · Supported formats: PNG, JPEG, BMP'
                    : 'Supported formats: PNG, JPEG, BMP',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              const PrivilegedActionNotice(),
              const SizedBox(height: 8),
              _ActionRow(
                canApply: bootLogoState.canApply,
                isApplying: bootLogoState.isApplying,
                onApply: () => _applyLogo(context, bootLogoBloc),
                onRestore: () => _restoreLogo(context, bootLogoBloc),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        AppRefreshButton(
          isBusy: state.isLoading,
          onPressed: state.isApplying
              ? null
              : () => bloc.add(const SettingsRefreshRequested()),
        ),
      ],
    );
  }

  Future<void> _pickFile(BootLogoBloc bloc) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp'],
      dialogTitle: 'Select Boot Logo Image',
    );
    final path = files.firstOrNull?.path;
    if (path != null) {
      bloc.add(BootLogoFileSelected(path));
    }
  }

  Future<void> _applyLogo(BuildContext context, BootLogoBloc bloc) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Apply Boot Logo',
      message:
          'This writes the selected image to EFI and updates UEFI variables. Changes appear after reboot.',
      confirmLabel: 'Apply',
    );
    if (confirmed && context.mounted) {
      bloc.add(const BootLogoApplyRequested());
    }
  }

  Future<void> _restoreLogo(BuildContext context, BootLogoBloc bloc) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Restore Default Logo',
      message:
          'This clears the custom boot logo flag in UEFI variables and restores the stock logo after reboot.',
      confirmLabel: 'Restore',
    );
    if (confirmed && context.mounted) {
      bloc.add(const BootLogoRestoreRequested());
    }
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.isBusy,
    required this.onChanged,
  });

  final ServiceControl service;
  final bool isBusy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppSwitchTile(
      value: service.targetEnabled,
      onChanged: service.supported && !isBusy ? onChanged : null,
      title: service.label,
      subtitle: _subtitle(service),
    );
  }

  String _subtitle(ServiceControl service) {
    if (!service.supported) {
      return 'Not available on this system';
    }

    final runtime = service.active ? 'running' : 'stopped';
    final boot = service.enabled ? 'enabled' : 'disabled';
    return '$runtime, $boot at boot • admin action';
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.isCustomEnabled,
    required this.dimensionLabel,
  });

  final bool isCustomEnabled;
  final String dimensionLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isCustomEnabled
              ? Icons.check_circle_outline
              : Icons.radio_button_unchecked,
          size: 18,
          color: isCustomEnabled
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            isCustomEnabled
                ? 'Custom logo active (target: $dimensionLabel)'
                : 'Stock logo active (target: $dimensionLabel)',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _FilePickerRow extends StatelessWidget {
  const _FilePickerRow({
    required this.selectedPath,
    required this.validationError,
    required this.isApplying,
    required this.onPick,
    required this.onClear,
  });

  final String? selectedPath;
  final String? validationError;
  final bool isApplying;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasPath = selectedPath != null && selectedPath!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: hasPath
                  ? Text(
                      selectedPath!,
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text(
                      'No image selected',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: isApplying ? null : onPick,
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('Browse...'),
            ),
            if (hasPath) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: isApplying ? null : onClear,
                tooltip: 'Clear selection',
              ),
            ],
          ],
        ),
        if (validationError != null) ...[
          const SizedBox(height: 4),
          Text(
            validationError!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.canApply,
    required this.isApplying,
    required this.onApply,
    required this.onRestore,
  });

  final bool canApply;
  final bool isApplying;
  final VoidCallback onApply;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FilledButton.icon(
          onPressed: canApply ? onApply : null,
          icon: isApplying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: YaruCircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.image_outlined),
          label: const Text('Apply Custom Logo'),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: isApplying ? null : onRestore,
          child: const Text('Restore Default'),
        ),
      ],
    );
  }
}
