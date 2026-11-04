import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

class PrivilegedActionNotice extends StatelessWidget {
  const PrivilegedActionNotice({
    super.key,
    this.message = 'Admin privileges required',
    this.compact = false,
  });

  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = compact
        ? scheme.onSurface.withValues(alpha: 0.7)
        : scheme.onSecondaryContainer;

    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: compact ? null : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(YaruIcons.lock, size: 16, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              message,
              style: compact
                  ? Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: foreground)
                  : TextStyle(color: foreground, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> confirmPrivilegedAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Continue',
}) async {
  final approved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      constraints: const BoxConstraints(maxWidth: 460),
      titlePadding: EdgeInsets.zero,
      title: YaruDialogTitleBar(title: Text(title)),
      contentPadding: const EdgeInsets.fromLTRB(
        kYaruPagePadding,
        kYaruPagePadding,
        kYaruPagePadding,
        0,
      ),
      content: Text(message, textAlign: TextAlign.left),
      actionsPadding: const EdgeInsets.all(kYaruPagePadding),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return approved ?? false;
}
