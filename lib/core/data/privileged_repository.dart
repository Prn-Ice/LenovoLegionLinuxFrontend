import 'package:flutter/foundation.dart';

import '../models/app_failure.dart';
import '../services/legion_frontend_bridge_service.dart';

/// Base class for repositories that issue privileged commands through the
/// [LegionFrontendBridgeService].
///
/// Centralizes the shared try/catch plumbing that every feature repository used
/// to duplicate: forwarding the command to the bridge and translating a
/// [LegionBridgeException] into the feature's own exception type via
/// [wrapBridgeError].
///
/// Repository writes default to a 5-second timeout, shorter than the bridge's
/// 15-second default. They use no retries and detect unavailable responses.
/// Subclasses must explicitly request a longer timeout or disable unavailable
/// response detection when the operation needs it.
abstract class PrivilegedRepository {
  const PrivilegedRepository({required this.bridgeService});

  @protected
  final LegionFrontendBridgeService bridgeService;

  /// Preserve the failure's kind and details in the feature exception.
  @protected
  Exception wrapBridgeError(AppFailure failure);

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
      throw wrapBridgeError(AppFailure.from(error, message: message));
    }
  }
}
