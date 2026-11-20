import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/system_services_provider.dart';
import '../../core/widgets/app_shell_components.dart';
import '../../core/widgets/privileged_action_notice.dart';

Future<void> requestPackagePowerAccess(
  BuildContext context,
  WidgetRef ref,
) async {
  final approved = await confirmPrivilegedAction(
    context,
    title: 'Show CPU power usage?',
    message: 'The app needs permission to read your CPU’s energy counter and show its power use in watts.',
    confirmLabel: 'Allow',
    cancelLabel: 'Skip',
  );
  if (!approved || !context.mounted) return;
  try {
    await ref.read(packagePowerTelemetryClientProvider).enable();
  } catch (error) {
    if (context.mounted) {
      await showAppErrorDialog(
        context,
        'CPU power is unavailable this session.\n\n$error',
      );
    }
  }
}
