import 'dart:convert';

import 'package:equatable/equatable.dart';

enum GraphicsMode {
  hybrid('hybrid', 'Hybrid'),
  hybridIgpuOnly('hybrid-igpu-only', 'Hybrid iGPU-only'),
  hybridAuto('hybrid-auto', 'Hybrid Auto'),
  discrete('discrete', 'Discrete');

  const GraphicsMode(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static GraphicsMode parse(Object? value) => switch (value) {
    'hybrid' => hybrid,
    'hybrid-igpu-only' => hybridIgpuOnly,
    'hybrid-auto' => hybridAuto,
    'discrete' => discrete,
    _ => throw FormatException('Unknown graphics mode: $value'),
  };
}

enum DgpuTopology {
  attached('attached', 'Attached'),
  detached('detached', 'Detached'),
  partial('partial', 'Partially attached'),
  unknown('unknown', 'Unknown');

  const DgpuTopology(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static DgpuTopology parse(Object? value) => switch (value) {
    'attached' => attached,
    'detached' => detached,
    'partial' => partial,
    'unknown' => unknown,
    _ => throw FormatException('Unknown dGPU topology: $value'),
  };
}

enum GraphicsReconciliation {
  settled('settled', 'Settled'),
  blocked('blocked', 'Blocked'),
  needed('needed', 'Needs reconciliation'),
  unknown('unknown', 'Unknown');

  const GraphicsReconciliation(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static GraphicsReconciliation parse(Object? value) => switch (value) {
    'settled' => settled,
    'blocked' => blocked,
    'needed' => needed,
    'unknown' => unknown,
    _ => throw FormatException('Unknown reconciliation state: $value'),
  };
}

class GraphicsModeClient extends Equatable {
  const GraphicsModeClient({
    required this.pid,
    required this.command,
    required this.devices,
  });

  final int pid;
  final String command;
  final List<String> devices;

  static GraphicsModeClient parse(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Graphics client must be an object.');
    }
    final pid = value['pid'];
    final command = value['comm'];
    final rawDevices = value['devices'];
    if (pid is! int || command is! String || rawDevices is! List) {
      throw const FormatException('Graphics client has invalid fields.');
    }
    final devices = rawDevices
        .map((device) {
          if (device is! String) {
            throw const FormatException(
              'Graphics client device must be a string.',
            );
          }
          return device;
        })
        .toList(growable: false);
    return GraphicsModeClient(pid: pid, command: command, devices: devices);
  }

  @override
  List<Object?> get props => [pid, command, devices];
}

class GraphicsModeStatus extends Equatable {
  const GraphicsModeStatus({
    required this.selectedMode,
    required this.effectiveState,
    required this.expectedState,
    required this.reconciliation,
    required this.clientInspectionComplete,
    required this.activeClients,
    required this.availableModes,
    required this.reconciliationAttempts,
  });

  final GraphicsMode selectedMode;
  final DgpuTopology effectiveState;
  final DgpuTopology expectedState;
  final GraphicsReconciliation reconciliation;
  final bool clientInspectionComplete;
  final List<GraphicsModeClient> activeClients;
  final List<GraphicsMode> availableModes;
  final int? reconciliationAttempts;

  static GraphicsModeStatus parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Invalid graphics status JSON: ${error.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Graphics status must be a JSON object.');
    }
    if (decoded['schema_version'] != 1) {
      throw FormatException(
        'Unsupported graphics status schema: ${decoded['schema_version']}',
      );
    }

    final inspectionComplete = decoded['client_inspection_complete'];
    final rawClients = decoded['active_clients'];
    final rawModes = decoded['available_modes'];
    final attempts = decoded['reconciliation_attempts'];
    if (inspectionComplete is! bool ||
        rawClients is! List ||
        rawModes is! List) {
      throw const FormatException('Graphics status has invalid fields.');
    }
    if (attempts != null && (attempts is! int || attempts < 0)) {
      throw const FormatException(
        'Reconciliation attempts must be an integer.',
      );
    }

    return GraphicsModeStatus(
      selectedMode: GraphicsMode.parse(decoded['selected_mode']),
      effectiveState: DgpuTopology.parse(decoded['effective_dgpu_state']),
      expectedState: DgpuTopology.parse(decoded['expected_dgpu_state']),
      reconciliation: GraphicsReconciliation.parse(decoded['reconciliation']),
      clientInspectionComplete: inspectionComplete,
      activeClients: rawClients
          .map(GraphicsModeClient.parse)
          .toList(growable: false),
      availableModes: rawModes.map(GraphicsMode.parse).toList(growable: false),
      reconciliationAttempts: attempts as int?,
    );
  }

  @override
  List<Object?> get props => [
    selectedMode,
    effectiveState,
    expectedState,
    reconciliation,
    clientInspectionComplete,
    activeClients,
    availableModes,
    reconciliationAttempts,
  ];
}
