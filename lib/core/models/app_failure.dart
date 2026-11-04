import 'package:equatable/equatable.dart';

import '../services/legion_control_client.dart';
import '../services/legion_frontend_bridge_service.dart';

enum AppFailureKind {
  generic,
  permissionDenied,
  privilegeSetup,
  unavailable,
  busy,
  timeout,
  graphicsBlocked,
  graphicsPending,
  commandFailed,
}

/// A displayable failure whose recovery meaning does not depend on its wording.
class AppFailure extends Equatable implements Exception {
  const AppFailure(
    this.message, {
    this.kind = AppFailureKind.generic,
    this.details,
  });

  final String message;
  final AppFailureKind kind;
  final String? details;

  /// Include raw diagnostics unless the action message already contains them.
  String get displayText {
    final rawDetails = details;
    if (rawDetails == null ||
        rawDetails.trim().isEmpty ||
        message.contains(rawDetails)) {
      return message;
    }
    return '$message\n\n$rawDetails';
  }

  /// Normalize unclassified errors without guessing their cause from text.
  factory AppFailure.from(Object error, {String? message}) {
    if (error is AppFailure) {
      if (message == null) return error;
      return AppFailure(message, kind: error.kind, details: error.details);
    }
    final kind = switch (error) {
      LegionBridgeException(:final code) => switch (code) {
        LegionBridgeErrorCode.permissionDenied =>
          AppFailureKind.permissionDenied,
        LegionBridgeErrorCode.privilegeSetup => AppFailureKind.privilegeSetup,
        LegionBridgeErrorCode.unavailable => AppFailureKind.unavailable,
        LegionBridgeErrorCode.busy => AppFailureKind.busy,
        LegionBridgeErrorCode.timeout => AppFailureKind.timeout,
        LegionBridgeErrorCode.graphicsBlocked => AppFailureKind.graphicsBlocked,
        LegionBridgeErrorCode.graphicsPending => AppFailureKind.graphicsPending,
        LegionBridgeErrorCode.commandFailed => AppFailureKind.commandFailed,
      },
      LegionControlSetupException() => AppFailureKind.privilegeSetup,
      LegionControlPermissionDeniedException() =>
        AppFailureKind.permissionDenied,
      LegionControlBusyException() => AppFailureKind.busy,
      LegionControlTimeoutException() => AppFailureKind.timeout,
      LegionControlGraphicsBlockedException() => AppFailureKind.graphicsBlocked,
      LegionControlGraphicsPendingException() => AppFailureKind.graphicsPending,
      LegionControlUnavailableException() ||
      LegionControlNotSupportedException() => AppFailureKind.unavailable,
      LegionControlCommandFailedException() => AppFailureKind.commandFailed,
      _ => AppFailureKind.generic,
    };
    return AppFailure(
      message ?? error.toString(),
      kind: kind,
      details: error is LegionBridgeException
          ? error.details
          : error.toString(),
    );
  }

  static AppFailure? optional(Object? error) =>
      error == null ? null : AppFailure.from(error);

  @override
  String toString() => message;

  @override
  List<Object?> get props => [message, kind, details];
}
