import 'package:equatable/equatable.dart';

class BridgeCommandRecord extends Equatable {
  const BridgeCommandRecord({
    required this.timestamp,
    required this.method,
    required this.args,
    required this.isPrivileged,
    required this.succeeded,
    required this.durationMs,
  });

  final DateTime timestamp;
  final String method;
  final List<String> args;
  final bool isPrivileged;
  final bool succeeded;
  final int durationMs;

  /// Returns [args] with any arg containing a `/` replaced by `<path>`.
  /// This prevents file-system paths (e.g. boot logo paths) from leaking
  /// personal directory names into exported diagnostics reports.
  List<String> get redactedArgs =>
      args.map((a) => a.contains('/') ? '<path>' : a).toList(growable: false);

  BridgeCommandRecord copyWith({
    DateTime? timestamp,
    String? method,
    List<String>? args,
    bool? isPrivileged,
    bool? succeeded,
    int? durationMs,
  }) {
    return BridgeCommandRecord(
      timestamp: timestamp ?? this.timestamp,
      method: method ?? this.method,
      args: args ?? this.args,
      isPrivileged: isPrivileged ?? this.isPrivileged,
      succeeded: succeeded ?? this.succeeded,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  @override
  List<Object?> get props => [
    timestamp,
    method,
    args,
    isPrivileged,
    succeeded,
    durationMs,
  ];
}
