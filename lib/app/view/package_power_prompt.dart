import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yaru/yaru.dart';

import '../../core/models/app_failure.dart';
import '../../core/widgets/app_shell_components.dart';
import '../../core/widgets/privileged_action_notice.dart';
import '../../features/sensors/view/package_power_access.dart';

const _hidePromptKey = 'hidePackagePowerPrompt';

Future<void> requestPackagePowerAccess(
  BuildContext context,
  WidgetRef ref, {
  required Box<dynamic> preferences,
}) async {
  if (preferences.get(_hidePromptKey) == true) return;

  var hidePrompt = false;
  final decision = await showDialog<({bool approved, bool hidePrompt})>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => PrivilegedActionDialog(
        title: 'Show CPU power usage?',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Allow access to your CPU’s energy counter to see power in watts for this session. You can also turn on readings later in Settings.',
            ),
            const SizedBox(height: 12),
            YaruCheckButton(
              contentPadding: EdgeInsets.zero,
              title: const Text('Don’t show again'),
              value: hidePrompt,
              onChanged: (checked) =>
                  setState(() => hidePrompt = checked ?? false),
            ),
          ],
        ),
        confirmLabel: 'Allow',
        cancelLabel: 'Skip',
        onDecision: (approved) =>
            Navigator.of(dialogContext)
                .pop((approved: approved, hidePrompt: hidePrompt)),
      ),
    ),
  );
  if (decision == null || !context.mounted) return;

  if (decision.hidePrompt) {
    try {
      await preferences.put(_hidePromptKey, true);
    } catch (error) {
      if (!context.mounted) return;
      await showAppErrorDialog(
        context,
        AppFailure(
          'Could not save your choice. The CPU power prompt will appear the next time you open the app.',
          details: error.toString(),
        ),
      );
    }
  }

  if (!decision.approved || !context.mounted) return;
  await setPackagePowerEnabled(context, ref, true);
}
