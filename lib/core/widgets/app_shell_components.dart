import 'package:flutter/material.dart';

enum AppStatusTone { error, notice }

class AppPageBody extends StatelessWidget {
  const AppPageBody({
    super.key,
    required this.title,
    this.errorMessage,
    this.noticeMessage,
    required this.children,
  });

  final String title;
  final String? errorMessage;
  final String? noticeMessage;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: textTheme.headlineMedium),
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

    final backgroundColor = isError
        ? scheme.errorContainer
        : scheme.primaryContainer;
    final foregroundColor = isError
        ? scheme.onErrorContainer
        : scheme.onPrimaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: foregroundColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: foregroundColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: foregroundColor)),
          ),
        ],
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
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: textTheme.titleLarge)),
                ...[trailing].nonNulls,
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(description!),
            ],
            if (children.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...children,
            ],
          ],
        ),
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
              child: CircularProgressIndicator(strokeWidth: 2),
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
    return SwitchListTile.adaptive(
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
