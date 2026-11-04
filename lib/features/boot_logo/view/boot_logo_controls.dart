import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/boot_logo_event.dart';
import '../providers/boot_logo_provider.dart';

/// Shared controls; the containing page owns the card and error presentation.
class BootLogoControls extends ConsumerWidget {
  const BootLogoControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bootLogoBlocProvider);

    if (state.isLoading && state.status == null) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.status == null)
          const YaruListTile(
            title: Text('Boot logo status unavailable'),
            subtitle: Text(
              'This feature requires a supported Lenovo Legion model and readable EFI variables.',
            ),
          )
        else ...[
          _StatusRow(
            isCustomEnabled: state.status!.isCustomEnabled,
            dimensionLabel: state.status!.dimensionLabel,
          ),
          const SizedBox(height: 16),
          _FilePickerRow(
            selectedPath: state.selectedImagePath,
            validationError: state.validationError,
            isApplying: state.isApplying,
            onPick: () => _pickFile(context, ref),
            onClear: () => ref
                .read(bootLogoBlocProvider.bloc)
                .add(const BootLogoFileSelected('')),
          ),
          const SizedBox(height: 8),
          Text(
            state.status!.hasDimensionConstraint
                ? 'Required dimensions: ${state.status!.dimensionLabel} · Supported formats: PNG, JPEG, BMP'
                : 'Supported formats: PNG, JPEG, BMP',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          const PrivilegedActionNotice(compact: true),
          const SizedBox(height: 8),
          _ActionRow(
            canApply: state.canApply,
            isApplying: state.isApplying,
            onApply: () => _applyLogo(context, ref),
            onRestore: () => _restoreLogo(context, ref),
          ),
        ],
      ],
    );
  }

  Future<void> _pickFile(BuildContext context, WidgetRef ref) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp'],
      dialogTitle: 'Select Boot Logo Image',
    );
    final path = files.firstOrNull?.path;
    if (context.mounted && path != null) {
      ref.read(bootLogoBlocProvider.bloc).add(BootLogoFileSelected(path));
    }
  }

  Future<void> _applyLogo(BuildContext context, WidgetRef ref) async {
    final selectedPath = ref.read(bootLogoBlocProvider).selectedImagePath;
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Apply Boot Logo',
      message:
          'This writes the selected image to EFI and updates UEFI variables. Changes appear after reboot.',
      confirmLabel: 'Apply',
    );
    if (confirmed &&
        context.mounted &&
        ref.read(bootLogoBlocProvider).canApply &&
        ref.read(bootLogoBlocProvider).selectedImagePath == selectedPath) {
      ref.read(bootLogoBlocProvider.bloc).add(const BootLogoApplyRequested());
    }
  }

  Future<void> _restoreLogo(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Restore Default Logo',
      message:
          'This clears the custom boot logo flag in UEFI variables and restores the stock logo after reboot.',
      confirmLabel: 'Restore',
    );
    if (confirmed &&
        context.mounted &&
        ref.read(bootLogoBlocProvider).status != null &&
        !ref.read(bootLogoBlocProvider).isApplying) {
      ref.read(bootLogoBlocProvider.bloc).add(const BootLogoRestoreRequested());
    }
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
          isCustomEnabled ? YaruIcons.ok : YaruIcons.radiobox,
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
              icon: const Icon(YaruIcons.folder_open, size: 16),
              label: const Text('Browse...'),
            ),
            if (hasPath) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(YaruIcons.window_close, size: 16),
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
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: canApply ? onApply : null,
          icon: isApplying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: YaruCircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(YaruIcons.image),
          label: const Text('Apply Custom Logo'),
        ),
        OutlinedButton(
          onPressed: isApplying ? null : onRestore,
          child: const Text('Restore Default'),
        ),
      ],
    );
  }
}
