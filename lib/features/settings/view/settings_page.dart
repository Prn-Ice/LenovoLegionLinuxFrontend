import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/models/control_mode.dart';
import 'hardware_access_controls.dart';
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
import '../../boot_logo/providers/boot_logo_provider.dart';
import '../../boot_logo/view/boot_logo_controls.dart';
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

    final appearance = _SettingsSection(
      title: 'Appearance',
      children: [
        Text('Theme', style: textTheme.titleSmall),
        const SizedBox(height: 12),
        _AppearanceSelector(
          selected: state.themeMode,
          onChanged: (mode) =>
              ref.read(settingsBlocProvider.bloc).add(ThemeModeChanged(mode)),
        ),
        const Divider(height: 32),
        Text('Accent follows power mode', style: textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Quiet, Balanced, Performance or Custom sets the accent '
          'throughout the app.',
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.56),
          ),
        ),
      ],
    );
    final backend = _SettingsSection(
      title: 'Backend',
      description: 'Choose hardware access and manage persistent services.',
      children: [
        const HardwareAccessControls(),
        const Divider(height: 32),
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
              '${snapshot.cliPath ?? 'Unavailable'}\n${snapshot.cliHealthSummary}',
            ),
          ),
        ],
        const PrivilegedActionNotice(compact: true),
        const SizedBox(height: 8),
        if (state.services.isEmpty)
          Text(
            state.activeControlMode == ControlMode.temporaryHelper
                ? 'Changing persistent services requires installed service mode.'
                : 'No service controls available.',
          ),
        ...state.services.map(
          (service) => _ServiceTile(
            service: service,
            isBusy: state.isApplying,
            onChanged: (enabled) async {
              final confirmed = await confirmPrivilegedAction(
                context,
                title: 'Update ${service.label}',
                message: 'Changing services may ask you to authenticate.',
                confirmLabel: 'Apply',
              );
              if (!context.mounted || !confirmed) {
                return;
              }
              final current = ref.read(settingsBlocProvider);
              if (current.isApplying ||
                  !current.services.any(
                    (item) => item.service == service.service && item.supported,
                  )) {
                return;
              }
              ref
                  .read(settingsBlocProvider.bloc)
                  .add(
                    SettingsServiceToggled(
                      serviceId: service.service.wireValue,
                      enabled: enabled,
                    ),
                  );
            },
          ),
        ),
      ],
    );
    final bootLogo = _SettingsSection(
      title: 'Boot Logo',
      description:
          'Set a custom logo shown during boot, or restore the stock Lenovo logo.',
      children: const [BootLogoControls()],
    );
    final deviceControls = _SettingsSection(
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
                    if (current.winKeySupported && !current.isApplying) {
                      ref
                          .read(devicesBlocProvider.bloc)
                          .add(WinKeySetRequested(enabled));
                    }
                  }
                : null,
          ),
          const Divider(height: 16),
          AppSwitchTile(
            title: 'Camera',
            value: devices.cameraEnabled ?? false,
            subtitle: devices.cameraSupported
                ? devices.cameraWriteSupported
                      ? boolEnabledLabel(devices.cameraEnabled)
                      : '${boolEnabledLabel(devices.cameraEnabled)} (Read-only)'
                : 'Not supported on this device',
            onChanged: null,
          ),
        ],
      ],
    );
    final displayControls = _SettingsSection(
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
                    if (current.overdriveSupported && !current.isApplying) {
                      ref
                          .read(displayBlocProvider.bloc)
                          .add(OverdriveModeSetRequested(enabled));
                    }
                  }
                : null,
          ),
          const Divider(height: 24),
          Text('Refresh Rate', style: textTheme.labelMedium),
          const SizedBox(height: 8),
          if (display.availableRefreshRates == null ||
              display.availableRefreshRates!.isEmpty)
            const Text('Unavailable — xrandr not accessible on this session.')
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
    );
    final aboutSection = _SettingsSection(
      title: 'About',
      children: [
        Row(
          children: [
            LegionMark(color: Theme.of(context).colorScheme.primary, size: 32),
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
        Text(about.snapshot?.hardwareModel ?? 'Device identity unavailable'),
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
          icon: const Icon(YaruIcons.document),
          label: const Text('Diagnostics and export'),
        ),
      ],
    );

    return AppPageBody(
      onErrorDismissed: (error) => ref
          .read(settingsBlocProvider.bloc)
          .add(ControlModeErrorDismissed(error)),
      errorMessage:
          state.controlModeErrorMessage ??
          state.appearanceErrorMessage ??
          state.errorMessage ??
          bootLogoState.errorMessage ??
          about.errorMessage ??
          devices.errorMessage ??
          display.errorMessage,
      children: [
        ResponsiveCardGrid(
          minCardWidth: 360,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                appearance,
                const SizedBox(height: 24),
                deviceControls,
                const SizedBox(height: 24),
                displayControls,
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                backend,
                const SizedBox(height: 24),
                bootLogo,
                const SizedBox(height: 24),
                aboutSection,
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _AppearanceSelector extends StatelessWidget {
  const _AppearanceSelector({required this.selected, required this.onChanged});

  final ThemeMode selected;
  final ValueChanged<ThemeMode> onChanged;

  static String _label(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth <
          300 * MediaQuery.textScalerOf(context).scale(1)) {
        return DropdownButtonFormField<ThemeMode>(
          initialValue: selected,
          key: ValueKey(selected),
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Appearance'),
          items: [
            for (final mode in ThemeMode.values)
              DropdownMenuItem(value: mode, child: Text(_label(mode))),
          ],
          onChanged: (mode) {
            if (mode != null) onChanged(mode);
          },
        );
      }
      return SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        segments: [
          for (final mode in ThemeMode.values)
            ButtonSegment(value: mode, label: Text(_label(mode))),
        ],
        selected: {selected},
        onSelectionChanged: (modes) => onChanged(modes.single),
      );
    },
  );
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
    required this.title,
    this.description,
    required this.children,
  });
  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.56);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(color: muted),
          ),
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (description != null) ...[
                Text(
                  description!,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                const SizedBox(height: 12),
              ],
              ...children,
            ],
          ),
        ),
      ],
    );
  }
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
