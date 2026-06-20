import 'package:flutter/foundation.dart';

import '../services/legion_frontend_bridge_service.dart';

/// Base class for repositories that issue privileged commands through the
/// [LegionFrontendBridgeService].
///
/// Centralizes the shared try/catch plumbing that every feature repository used
/// to duplicate: forwarding the command to the bridge and translating a
/// [LegionBridgeException] into the feature's own exception type via
/// [wrapBridgeError].
///
/// Defaults intentionally mirror [LegionFrontendBridgeService.runPrivilegedCommand]
/// (`timeout` 5s, `detectUnavailableResponse` true) so subclasses that relied on
/// the bridge defaults need no call-site changes. Subclasses that need other
/// values (e.g. a longer timeout, or suppressing unavailable-response detection)
/// must pass them explicitly at the call site.
abstract class PrivilegedRepository {
  const PrivilegedRepository({required this.bridgeService});

  @protected
  final LegionFrontendBridgeService bridgeService;

  /// Wrap a bridge failure message in the feature-specific exception type.
  @protected
  Exception wrapBridgeError(String message);

  @protected
  Future<void> runPrivilegedCommand(
    List<String> args, {
    required String method,
    required String failurePrefix,
    Duration timeout = const Duration(seconds: 5),
    bool detectUnavailableResponse = true,
  }) async {
    try {
      await bridgeService.runPrivilegedCommand(
        method: method,
        args: args,
        timeout: timeout,
        detectUnavailableResponse: detectUnavailableResponse,
      );
    } on LegionBridgeException catch (error) {
      final details = error.details;
      final message = details.isEmpty
          ? '$failurePrefix.'
          : '$failurePrefix: $details';
      throw wrapBridgeError(message);
    }
  }
}
