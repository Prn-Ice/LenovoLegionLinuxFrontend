import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/app_failure.dart';
import '../../../core/widgets/app_shell_components.dart';
import '../bloc/package_power_cubit.dart';

Future<void> setPackagePowerEnabled(
  BuildContext context,
  WidgetRef ref,
  bool enabled,
) async {
  try {
    await ref.read(packagePowerProvider.bloc).setEnabled(enabled);
  } on AppFailure catch (error) {
    if (context.mounted) await showAppErrorDialog(context, error);
  }
}
