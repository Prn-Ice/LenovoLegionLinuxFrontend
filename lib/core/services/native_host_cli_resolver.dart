import 'package:flutter/services.dart';

import 'legion_control_client.dart';

/// Selects a canonical CLI for unprivileged reads from fixed host locations.
/// The root helper independently validates this selection before writes.
Future<String> resolveNativeHostCli() async {
  try {
    final path = await const MethodChannel('io.github.prnice.legion/control')
        .invokeMethod<Object>('findHostCli')
        .timeout(const Duration(seconds: 5));
    if (path is! String || !path.startsWith('/') || path.contains('\u0000')) {
      throw const ControlHelperSetupException(
        'The host did not report a valid installed legion_cli path.',
      );
    }
    return path;
  } on ControlHelperSetupException {
    rethrow;
  } catch (error) {
    throw ControlHelperSetupException(
      'Could not select the installed legion_cli. Check the CLI installation and restart the app. $error',
    );
  }
}
