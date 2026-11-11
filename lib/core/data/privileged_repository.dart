import 'package:flutter/foundation.dart';

import '../models/app_failure.dart';
import '../services/legion_control_client.dart';
import '../services/legion_frontend_bridge_service.dart';

/// Base class for repositories that issue privileged commands through the
/// [LegionFrontendBridgeService].
///
/// Centralizes error handling for repositories by forwarding commands to the
/// bridge and translating [LegionBridgeException] into the feature exception
/// through [wrapBridgeError].
///
/// Repository writes default to a 5-second timeout, shorter than the bridge's
/// 15-second default. Subclasses explicitly request longer timeouts when needed.
abstract class PrivilegedRepository {
  const PrivilegedRepository({required this.bridgeService});

  @protected
  final LegionFrontendBridgeService bridgeService;

  /// Preserve the failure's kind and details in the feature exception.
  @protected
  Exception wrapBridgeError(AppFailure failure);

  @protected
  Future<void> runControlOperation(
    Future<void> Function(LegionControlClient) operation, {
    required String method,
    List<String> args = const [],
    required String failurePrefix,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      await bridgeService.runControlOperation(
        operation: operation,
        method: method,
        args: args,
        timeout: timeout,
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
