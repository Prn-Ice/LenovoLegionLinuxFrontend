import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaru/yaru.dart';

const _nixosControlConfiguration = '''security.polkit.enable = true;
services.legionControl = {
  enable = true;
  backendPackage = pkgs.lenovo-legion;
};''';

class AppPageBody extends StatelessWidget {
  const AppPageBody({
    super.key,
    this.title,
    this.subtitle,
    this.headerAction,
    this.errorMessage,
    required this.children,
  });

  final String? title;
  final Widget? subtitle;

  /// Optional action shown at the top-right of the page header (e.g. refresh).
  final Widget? headerAction;
  final String? errorMessage;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppErrorDialogListener(
      errorMessage: errorMessage,
      child: ListView(
        padding: const EdgeInsets.all(kYaruPagePadding),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 4),
                                DefaultTextStyle(
                                  style: textTheme.bodySmall!,
                                  child: subtitle!,
                                ),
                              ],
                            ],
                          ),
                        ),
                        ?headerAction,
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  ...children,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppErrorDialogListener extends StatefulWidget {
  const AppErrorDialogListener({
    super.key,
    this.errorMessage,
    required this.child,
  });

  final String? errorMessage;
  final Widget child;

  @override
  State<AppErrorDialogListener> createState() => _AppErrorDialogListenerState();
}

class _AppErrorDialogListenerState extends State<AppErrorDialogListener> {
  bool _dialogVisible = false;
  String? _pendingMessage;

  @override
  void initState() {
    super.initState();
    _scheduleDialog(widget.errorMessage);
  }

  @override
  void didUpdateWidget(covariant AppErrorDialogListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.errorMessage != widget.errorMessage) {
      _scheduleDialog(widget.errorMessage);
    }
  }

  void _scheduleDialog(String? message) {
    if (message == null || message.trim().isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showDialog(message);
    });
  }

  Future<void> _showDialog(String message) async {
    if (_dialogVisible) {
      _pendingMessage = message;
      return;
    }

    _dialogVisible = true;
    await showAppErrorDialog(context, message);
    if (!mounted) return;
    _dialogVisible = false;

    final pendingMessage = _pendingMessage;
    _pendingMessage = null;
    if (pendingMessage != null && pendingMessage != message) {
      _scheduleDialog(pendingMessage);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> showAppErrorDialog(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AppErrorDialog(message: message),
  );
}

class AppErrorDialog extends StatefulWidget {
  const AppErrorDialog({super.key, required this.message});

  final String message;

  @override
  State<AppErrorDialog> createState() => _AppErrorDialogState();
}

class _AppErrorDialogState extends State<AppErrorDialog> {
  bool _configurationCopied = false;
  bool _detailsCopied = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final errorKind = _classifyAppError(widget.message);
    final isPrivilegeSetup = errorKind == _AppErrorKind.privilegeSetup;
    final title = switch (errorKind) {
      _AppErrorKind.privilegeSetup => 'Privileged access needs setup',
      _AppErrorKind.graphicsBlocked => 'Graphics change blocked',
      _AppErrorKind.graphicsPending => 'Graphics policy did not settle',
      _AppErrorKind.generic => 'Action could not be completed',
    };
    final consequence = switch (errorKind) {
      _AppErrorKind.graphicsBlocked =>
        'The protected preflight stopped this change before firmware was written.',
      _AppErrorKind.graphicsPending =>
        'Firmware accepted the selected policy, but the requested GPU topology was not confirmed.',
      _ =>
        'The requested action did not complete. No confirmation was received that the setting changed.',
    };

    return AlertDialog(
      title: YaruDialogTitleBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 20, color: scheme.error),
            const SizedBox(width: 8),
            Flexible(child: Text(title)),
          ],
        ),
      ),
      titlePadding: EdgeInsets.zero,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: SelectionArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: isPrivilegeSetup
                  ? _buildPrivilegeSetupContent(context)
                  : [
                      Text(consequence),
                      const SizedBox(height: 16),
                      Text('Details', style: textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Text(widget.message),
                    ],
            ),
          ),
        ),
      ),
      actions: [
        if (!isPrivilegeSetup)
          TextButton.icon(
            onPressed: _copyDetails,
            icon: Icon(
              _detailsCopied ? Icons.check : Icons.copy_outlined,
              size: 18,
            ),
            label: Text(_detailsCopied ? 'Copied' : 'Copy details'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  List<Widget> _buildPrivilegeSetupContent(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return [
      const Text(
        'The app could not reach its privileged control service, so the requested system change was not made.',
      ),
      const SizedBox(height: 16),
      Text('What this means', style: textTheme.titleSmall),
      const SizedBox(height: 6),
      const Text(
        'legion-control is a narrowly scoped system service that applies supported hardware changes after Polkit authorizes this app. The service or its policy is not available in this installation.',
      ),
      const SizedBox(height: 16),
      Text('NixOS', style: textTheme.titleSmall),
      const SizedBox(height: 6),
      const Text(
        'Import the frontend NixOS module, enable the control service and Polkit, rebuild NixOS, then try the action again.',
      ),
      const SizedBox(height: 10),
      DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'System configuration',
                      style: textTheme.labelMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _copyConfiguration,
                    icon: Icon(
                      _configurationCopied ? Icons.check : Icons.copy_outlined,
                      size: 17,
                    ),
                    label: Text(_configurationCopied ? 'Copied' : 'Copy'),
                  ),
                ],
              ),
              Text(
                _nixosControlConfiguration,
                style: textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text('Other Linux distributions', style: textTheme.titleSmall),
      const SizedBox(height: 6),
      const Text(
        'Install the legion-control systemd unit, D-Bus policy, and Polkit action supplied in packaging/, then enable Polkit and start legion-control.service.',
      ),
      const SizedBox(height: 16),
      Text('Technical details', style: textTheme.titleSmall),
      const SizedBox(height: 6),
      Text(
        widget.message,
        style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    ];
  }

  Future<void> _copyConfiguration() async {
    if (mounted) setState(() => _configurationCopied = true);
    try {
      await Clipboard.setData(
        const ClipboardData(text: _nixosControlConfiguration),
      );
    } catch (_) {
      if (mounted) setState(() => _configurationCopied = false);
      rethrow;
    }
  }

  Future<void> _copyDetails() async {
    if (mounted) setState(() => _detailsCopied = true);
    try {
      await Clipboard.setData(ClipboardData(text: widget.message));
    } catch (_) {
      if (mounted) setState(() => _detailsCopied = false);
      rethrow;
    }
  }
}

bool _isPrivilegeSetupError(String message) {
  final normalized = message.toLowerCase();
  return normalized.contains(
        'legion-control service could not provide privileged access',
      ) ||
      normalized.contains('legion-control service is not configured') ||
      normalized.contains('org.freedesktop.dbus.error.serviceunknown');
}

enum _AppErrorKind { generic, privilegeSetup, graphicsBlocked, graphicsPending }

_AppErrorKind _classifyAppError(String message) {
  if (_isPrivilegeSetupError(message)) return _AppErrorKind.privilegeSetup;
  if (message.contains(
    'firmware policy was not changed because the privileged preflight',
  )) {
    return _AppErrorKind.graphicsBlocked;
  }
  if (message.contains('effective GPU topology did not settle')) {
    return _AppErrorKind.graphicsPending;
  }
  return _AppErrorKind.generic;
}

class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.title,
    this.description,
    this.trailing,
    required this.children,
  });

  final String title;
  final String? description;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return YaruSection(
      headline: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Expanded(child: Text(title, style: textTheme.titleMedium)),
            ?trailing,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description != null) ...[
            Text(description!),
            const SizedBox(height: 8),
          ],
          if (children.isNotEmpty) ...children,
        ],
      ),
    );
  }
}

class AppRefreshButton extends StatelessWidget {
  const AppRefreshButton({
    super.key,
    required this.isBusy,
    this.onPressed,
    this.label = 'Refresh',
  });

  final bool isBusy;
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: isBusy ? null : onPressed,
      icon: isBusy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: YaruCircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
      label: Text(label),
    );
  }
}

class AppSwitchTile extends StatelessWidget {
  const AppSwitchTile({
    super.key,
    required this.value,
    required this.title,
    this.subtitle,
    this.onChanged,
    this.contentPadding = EdgeInsets.zero,
  });

  final bool value;
  final String title;
  final String? subtitle;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    return YaruSwitchListTile(
      contentPadding: contentPadding,
      value: value,
      onChanged: onChanged,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
    );
  }
}

String boolEnabledLabel(
  bool? value, {
  String unavailableLabel = 'Unavailable on this device',
}) {
  if (value == null) {
    return unavailableLabel;
  }

  return value ? 'Enabled' : 'Disabled';
}

/// A feature-page section card with a leading icon and optional background tint.
/// Use instead of [AppSectionCard] for interactive control sections.
class AppControlCard extends StatelessWidget {
  const AppControlCard({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.trailing,
    this.tint,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? trailing;
  final Color? tint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Widget section = YaruSection(
      headline: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: textTheme.titleMedium)),
            ?trailing,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description != null) ...[
            Text(description!, style: textTheme.bodySmall),
            const SizedBox(height: 8),
          ],
          ...children,
        ],
      ),
    );

    if (tint != null) {
      section = ColoredBox(
        color: tint!.withValues(alpha: 0.06),
        child: section,
      );
    }

    return section;
  }
}

/// A dashboard-specific card with an icon, optional background tint,
/// and slightly more visual weight than [AppControlCard].
class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    this.tint,
    required this.children,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final Color? tint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: tint != null
          ? Color.alphaBlend(tint!.withValues(alpha: 0.08), scheme.surface)
          : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: textTheme.titleMedium)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
