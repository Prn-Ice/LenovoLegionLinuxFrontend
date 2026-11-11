import 'package:flutter/services.dart';

import 'legion_control_client.dart';

/// Resolves a canonical CLI from administrator-controlled host locations.
/// This method inspects paths without launching the control helper.
Future<String> resolveNativeHostCli() async {
  try {
    final path = await const MethodChannel(
      'io.github.prnice.legion/portable_control',
    ).invokeMethod<Object>('findHostCli').timeout(const Duration(seconds: 5));
    if (path is! String || !path.startsWith('/') || path.contains('\u0000')) {
      throw const LegionControlPortableSetupException(
        'The host did not report a valid installed legion_cli path.',
      );
    }
    return path;
  } on LegionControlPortableSetupException {
    rethrow;
  } catch (error) {
    throw LegionControlPortableSetupException(
      'Could not select the installed legion_cli. Check the CLI installation and restart the app. $error',
    );
  }
}
