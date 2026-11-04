import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../../../core/widgets/responsive_card_grid.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../core/widgets/legion_mark.dart';
import '../../about/providers/about_provider.dart';
import '../../devices/bloc/devices_event.dart';
import '../../devices/providers/devices_provider.dart';
import '../../display/bloc/display_event.dart';
import '../../display/providers/display_provider.dart';
import '../../diagnostics/view/diagnostics_page.dart';
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
    final bootLogoState = ref.watch(bootLogoBlocProvider);
    final about = ref.watch(aboutBlocProvider);
    final devices = ref.watch(devicesBlocProvider);
    final display = ref.watch(displayBlocProvider);

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    final textTheme = Theme.of(context).textTheme;

    return AppPageBody(
      errorMessage:
          state.appearanceErrorMessage ??
          state.errorMessage ??
          bootLogoState.errorMessage ??
          about.errorMessage ??
          devices.errorMessage ??
          display.errorMessage,
      children: [
        ResponsiveCardGrid(
          minCardWidth: 380,
          children: [
            _SettingsSection(
              icon: YaruIcons.settings,
              title: 'Appearance',
              children: [
                const SizedBox(height: 4),
                Text('Theme', style: textTheme.labelMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final mode in ThemeMode.values)
                      _SettingsChoiceChip(
                        label: switch (mode) {
                          ThemeMode.system => 'System',
                          ThemeMode.light => 'Light',
                          ThemeMode.dark => 'Dark',
                        },
                        selected: state.themeMode == mode,
                        onSelected: () => ref
                            .read(settingsBlocProvider.bloc)
                            .add(ThemeModeChanged(mode)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                AppSwitchTile(
                  title: 'Follow power mode accent',
                  value: state.accentFollowsPowerMode,
                  subtitle:
                      'Use the current power mode colour. If the mode is '
                      'unavailable, use your saved manual or system accent.',
                  onChanged: (enabled) => ref
                      .read(settingsBlocProvider.bloc)
                      .add(AccentFollowsPowerModeChanged(enabled)),
                ),
                if (state.accentFollowsPowerMode)
                  Text(
                    'Manual accent is saved. Turn off Follow power mode accent '
                    'to restore or change it.',
                    style: textTheme.bodySmall,
                  ),
                Text('Accent colour', style: textTheme.labelMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SettingsChoiceChip(
                      label: 'System accent',
                      selected: state.yaruVariant == null,
                      onSelected: state.accentFollowsPowerMode
                          ? null
                          : () => ref
                                .read(settingsBlocProvider.bloc)
                                .add(const YaruVariantChanged(null)),
                    ),
                    ...YaruVariant.accents.map((variant) {
                      final selected = state.yaruVariant == variant;
                      return Semantics(
                        label: '${variant.name} accent colour',
                        button: true,
                        selected: selected,
                        enabled: !state.accentFollowsPowerMode,
                        child: Opacity(
                          opacity: state.accentFollowsPowerMode ? 0.38 : 1,
                          child: InkWell(
                            onTap: state.accentFollowsPowerMode
                                ? null
                                : () => ref
                                      .read(settingsBlocProvider.bloc)
                                      .add(
                                        YaruVariantChanged(
                                          selected ? null : variant,
                                        ),
                                      ),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: variant.color,
                                border: selected
                                    ? Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                        width: 2.5,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
            _SettingsSection(
              icon: YaruIcons.settings,
              title: 'Backend',
              description:
                  'Enable or disable Linux service dependencies used by Legion tooling.',
              children: [
                if (about.snapshot case final snapshot?) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Module version'),
                    subtitle: Text(snapshot.moduleVersion ?? 'Unknown'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('CLI'),
                    subtitle: SelectableText(
                      '${snapshot.cliPath}\n${snapshot.cliHealthSummary}',
                    ),
                  ),
                ],
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
                      final current = ref.read(settingsBlocProvider);
                      if (current.isApplying ||
                          !current.services.any(
                            (item) => item.id == service.id && item.supported,
                          )) {
                        return;
                      }
                      ref
                          .read(settingsBlocProvider.bloc)
                          .add(
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
            _SettingsSection(
              icon: YaruIcons.image,
              title: 'Boot Logo',
              description:
                  'Set a custom logo shown during boot, or restore the stock Lenovo logo.',
              children: [
                if (bootLogoState.isLoading && bootLogoState.status == null)
                  const Center(child: YaruCircularProgressIndicator())
                else if (bootLogoState.status == null)
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
                    onPick: () => _pickFile(context, ref),
                    onClear: () => ref
                        .read(bootLogoBlocProvider.bloc)
                        .add(const BootLogoFileSelected('')),
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
                    onApply: () => _applyLogo(context, ref),
                    onRestore: () => _restoreLogo(context, ref),
                  ),
                ],
              ],
            ),
            _SettingsSection(
              icon: YaruIcons.keyboard,
              title: 'Devices',
              children: [
                if (devices.isLoading && !devices.hasLoaded)
                  const Center(child: YaruCircularProgressIndicator())
                else ...[
                  AppSwitchTile(
                    title: 'Win Key',
                    value: devices.winKeyEnabled ?? false,
                    subtitle: devices.winKeySupported
                        ? boolEnabledLabel(devices.winKeyEnabled)
                        : 'Not supported on this device',
                    onChanged: devices.winKeySupported && !devices.isApplying
                        ? (enabled) async {
                            final confirmed = await confirmPrivilegedAction(
                              context,
                              title: 'Change Win Key',
                              message:
                                  'Changing the Win Key uses privileged access and may prompt for authentication.',
                              confirmLabel: 'Apply',
                            );
                            if (!context.mounted || !confirmed) return;
                            final current = ref.read(devicesBlocProvider);
                            if (current.winKeySupported &&
                                !current.isApplying) {
                              ref
                                  .read(devicesBlocProvider.bloc)
                                  .add(WinKeySetRequested(enabled));
                            }
                          }
                        : null,
                  ),
                  AppSwitchTile(
                    title: 'Camera',
                    value: devices.cameraEnabled ?? false,
                    subtitle: devices.cameraSupported
                        ? '${boolEnabledLabel(devices.cameraEnabled)} (read-only)'
                        : 'Not supported on this device',
                    onChanged: null,
                  ),
                ],
              ],
            ),
            _SettingsSection(
              icon: YaruIcons.monitor,
              title: 'Display',
              children: [
                if (display.isLoading && !display.hasLoaded)
                  const Center(child: YaruCircularProgressIndicator())
                else ...[
                  AppSwitchTile(
                    title: 'Overdrive',
                    value: display.overdriveEnabled ?? false,
                    subtitle: display.overdriveSupported
                        ? boolEnabledLabel(display.overdriveEnabled)
                        : 'Not supported on this device',
                    onChanged: display.overdriveSupported && !display.isApplying
                        ? (enabled) async {
                            final confirmed = await confirmPrivilegedAction(
                              context,
                              title: 'Toggle overdrive',
                              message:
                                  'Changing overdrive uses privileged access and may prompt for authentication.',
                              confirmLabel: 'Apply',
                            );
                            if (!context.mounted || !confirmed) return;
                            final current = ref.read(displayBlocProvider);
                            if (current.overdriveSupported &&
                                !current.isApplying) {
                              ref
                                  .read(displayBlocProvider.bloc)
                                  .add(OverdriveModeSetRequested(enabled));
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text('Refresh Rate', style: textTheme.labelMedium),
                  const SizedBox(height: 8),
                  if (display.availableRefreshRates == null ||
                      display.availableRefreshRates!.isEmpty)
                    const Text(
                      'Unavailable — xrandr not accessible on this session.',
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final rate in display.availableRefreshRates!)
                          _SettingsChoiceChip(
                            label: '${rate.round()} Hz',
                            selected: rate == display.currentRefreshRate,
                            onSelected: display.isApplying
                                ? null
                                : () => ref
                                      .read(displayBlocProvider.bloc)
                                      .add(RefreshRateSetRequested(rate)),
                          ),
                      ],
                    ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
            _SettingsSection(
              icon: YaruIcons.information,
              title: 'About',
              children: [
                Row(
                  children: [
                    LegionMark(
                      color: Theme.of(context).colorScheme.primary,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Lenovo Legion Linux Frontend',
                        style: textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  about.snapshot?.hardwareModel ??
                      'Device identity unavailable',
                ),
                Text('Kernel: ${about.snapshot?.kernelVersion ?? 'Unknown'}'),
                const _AboutLinks(),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        appBar: _DiagnosticsTitleBar(),
                        body: DiagnosticsPage(),
                      ),
                    ),
                  ),
                  icon: const Icon(YaruIcons.image),
                  label: const Text('Diagnostics and export'),
                ),
              ],
            ),
          ],
        ),
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

class _SettingsChoiceChip extends StatelessWidget {
  const _SettingsChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: scheme.primary,
      labelStyle: selected ? TextStyle(color: scheme.onPrimary) : null,
      checkmarkColor: scheme.onPrimary,
      onSelected: onSelected == null ? null : (_) => onSelected!(),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    this.description,
    required this.children,
  });
  final IconData icon;
  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(description!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
}

class _AboutLinks extends StatefulWidget {
  const _AboutLinks();
  @override
  State<_AboutLinks> createState() => _AboutLinksState();
}

class _AboutLinksState extends State<_AboutLinks> {
  String? copied;
  late Future<String> manifest;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    manifest = DefaultAssetBundle.of(
      context,
    ).loadString('pubspec.yaml', cache: false);
  }

  Future<void> copyLink(String label, String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) setState(() => copied = label);
    } catch (error) {
      if (mounted) {
        setState(() => copied = null);
        await showAppErrorDialog(context, 'Could not copy $label link: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FutureBuilder<String>(
        future: manifest,
        builder: (context, snapshot) {
          final version = RegExp(
            r'^version:\s*(\S+)',
            multiLine: true,
          ).firstMatch(snapshot.data ?? '')?.group(1);
          return Text(
            'Manifest version: ${version ?? (snapshot.connectionState == ConnectionState.done ? 'Unavailable' : 'Loading…')}',
          );
        },
      ),
      const SizedBox(height: 8),
      const Text('Copy a link to open it in your browser.'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => copyLink(
              'GitHub',
              'https://github.com/Prn-Ice/LenovoLegionLinuxFrontend',
            ),
            icon: Icon(
              copied == 'GitHub' ? YaruIcons.checkbox_checked : YaruIcons.copy,
            ),
            label: Text(
              copied == 'GitHub' ? 'Copied GitHub link' : 'Copy GitHub link',
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => copyLink(
              'issue',
              'https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/issues/new',
            ),
            icon: Icon(
              copied == 'issue' ? YaruIcons.checkbox_checked : YaruIcons.copy,
            ),
            label: Text(
              copied == 'issue' ? 'Copied issue link' : 'Copy issue link',
            ),
          ),
        ],
      ),
    ],
  );
}

class _DiagnosticsTitleBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _DiagnosticsTitleBar();

  @override
  Size get preferredSize => const Size.fromHeight(kYaruTitleBarHeight);

  @override
  Widget build(BuildContext context) => YaruWindowTitleBar(
    title: const Text('Diagnostics'),
    centerTitle: false,
    leading: BackButton(onPressed: () => Navigator.of(context).pop()),
  );
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
