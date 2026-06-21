import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

enum AppStatusTone { error, notice }

class AppPageBody extends StatelessWidget {
  const AppPageBody({
    super.key,
    required this.title,
    this.subtitle,
    this.headerAction,
    this.errorMessage,
    this.noticeMessage,
    required this.children,
  });

  final String title;
  final Widget? subtitle;

  /// Optional action shown at the top-right of the page header (e.g. refresh).
  final Widget? headerAction;
  final String? errorMessage;
  final String? noticeMessage;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(kYaruPagePadding),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
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
                if (errorMessage != null || noticeMessage != null) ...[
                  AppStatusMessages(
                    errorMessage: errorMessage,
                    noticeMessage: noticeMessage,
                  ),
                  const SizedBox(height: 12),
                ],
                ...children,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AppStatusMessages extends StatelessWidget {
  const AppStatusMessages({super.key, this.errorMessage, this.noticeMessage});

  final String? errorMessage;
  final String? noticeMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (errorMessage != null)
          AppStatusBanner(message: errorMessage!, tone: AppStatusTone.error),
        if (errorMessage != null && noticeMessage != null)
          const SizedBox(height: 8),
        if (noticeMessage != null)
          AppStatusBanner(message: noticeMessage!, tone: AppStatusTone.notice),
      ],
    );
  }
}

class AppStatusBanner extends StatelessWidget {
  const AppStatusBanner({super.key, required this.message, required this.tone});

  final String message;
  final AppStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isError = tone == AppStatusTone.error;

    return YaruBanner.tile(
      color: isError ? scheme.errorContainer : scheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      icon: Icon(
        isError ? Icons.error_outline : Icons.info_outline,
        color: isError ? scheme.onErrorContainer : scheme.onPrimaryContainer,
      ),
      title: Text(
        message,
        style: TextStyle(
          color: isError ? scheme.onErrorContainer : scheme.onPrimaryContainer,
        ),
      ),
    );
  }
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
