import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:legion_frontend/core/models/control_capabilities.dart';
import 'package:legion_frontend/core/providers/system_services_provider.dart';
import 'package:legion_frontend/core/services/legion_cli_service.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/services/legion_frontend_bridge_service.dart';
import 'package:legion_frontend/features/dgpu/models/dgpu_process.dart';
import 'package:legion_frontend/features/dgpu/models/graphics_mode.dart';
import 'package:legion_frontend/features/dgpu/providers/dgpu_provider.dart';
import 'package:legion_frontend/features/dgpu/repository/dgpu_repository.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_bloc.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_event.dart';

/// Synthetic graphics state and typed control writes for the native journey.
/// The fixture never reads or writes host PCI, process, or CLI state.
class SafeGraphicsFixture {
  SafeGraphicsFixture({
    this.availableModes = const [
      GraphicsMode.hybrid,
      GraphicsMode.hybridIgpuOnly,
      GraphicsMode.discrete,
    ],
  });

  final List<GraphicsMode> availableModes;
  GraphicsMode selectedMode = GraphicsMode.hybrid;
  bool failAuthorization = false;
  bool failWrite = false;
  bool statusUnavailable = false;
  bool returnUnknownStatus = false;
  DgpuTopology effectiveState = DgpuTopology.attached;
  DgpuTopology expectedState = DgpuTopology.attached;
  GraphicsReconciliation reconciliation = GraphicsReconciliation.settled;
  ({DgpuTopology effective, DgpuTopology expected})? observedAfterWrite;
  int statusReads = 0;
  final requests = <GraphicsMode>[];
  final writes = <GraphicsMode>[];
  final rejectedCommands = <List<String>>[];
  int authorizations = 0;
  final closed = Completer<void>();

  String get statusJson => jsonEncode({
    'schema_version': 1,
    'selected_mode': returnUnknownStatus
        ? 'future-mode'
        : selectedMode.wireValue,
    'effective_dgpu_state': effectiveState.wireValue,
    'expected_dgpu_state': expectedState.wireValue,
    'reconciliation': reconciliation.wireValue,
    'client_inspection_complete': true,
    'active_clients': const [],
    'available_modes': availableModes.map((mode) => mode.wireValue).toList(),
  });
}

List<Override> safeGraphicsOverrides(SafeGraphicsFixture fixture) {
  final cli = LegionCliService(
    cliPath: '/integration-test/graphics-fixture',
    processRunner: (_, arguments) async {
      if (arguments.contains('graphics-mode') &&
          arguments.contains('status') &&
          arguments.contains('--json')) {
        fixture.statusReads++;
        if (fixture.statusUnavailable) {
          fixture.rejectedCommands.add(List.unmodifiable(arguments));
          return ProcessResult(0, 2, '', 'graphics mode unsupported');
        }
        return ProcessResult(0, 0, fixture.statusJson, '');
      }
      fixture.rejectedCommands.add(List.unmodifiable(arguments));
      return ProcessResult(0, 2, '', 'unsupported graphics fixture command');
    },
  );
  return [
    legionBridgeServiceProvider.overrideWith((ref) {
      final client = LegionControlClient(
        transport: _GraphicsTransport(fixture),
      );
      final bridge = LegionFrontendBridgeService(
        cliService: cli,
        controlClient: client,
      );
      ref.onDispose(() {
        cli.close();
        unawaited(client.close());
      });
      return bridge;
    }),
    dgpuRepositoryProvider.overrideWith((ref) {
      return DgpuRepository(
        bridgeService: ref.watch(legionBridgeServiceProvider),
        findPciAddress: () async => '0000:01:00.0',
        readRuntimeStatus: (_) async => true,
        queryComputeProcesses: () async => const <DgpuProcess>[],
        queryPciName: (_) async => 'Synthetic NVIDIA GPU',
      );
    }),
    dgpuBlocProvider.overrideWith(
      (ref) => DgpuBloc(
        repository: ref.watch(dgpuRepositoryProvider),
        pollInterval: const Duration(days: 1),
      )..add(const DgpuStarted()),
    ),
  ];
}

class _GraphicsTransport extends LegionControlTransport {
  _GraphicsTransport(this.fixture);

  final SafeGraphicsFixture fixture;

  @override
  Future<ControlCapabilities> getCapabilities() async => ControlCapabilities(
    protocolVersion: ControlCapabilities.currentProtocolVersion,
    supported: const [ControlCapability.interactiveControl],
  );

  @override
  Future<void> authorize() async {
    fixture.authorizations++;
    if (fixture.failAuthorization) {
      fixture.failAuthorization = false;
      throw const LegionControlPermissionDeniedException(
        'Synthetic graphics authorization was denied.',
      );
    }
  }

  @override
  Future<void> call(String method, List<Object> arguments) async {
    if (method != 'SetGraphicsMode' ||
        arguments.length != 1 ||
        arguments.single is! String) {
      fixture.rejectedCommands.add([
        method,
        ...arguments.map((argument) => '$argument'),
      ]);
      throw StateError(
        'Unexpected graphics fixture operation: $method $arguments',
      );
    }
    final mode = GraphicsMode.values
        .where((value) => value.wireValue == arguments.single)
        .firstOrNull;
    if (mode == null || !fixture.availableModes.contains(mode)) {
      fixture.rejectedCommands.add([
        method,
        ...arguments.map((argument) => '$argument'),
      ]);
      throw const LegionControlNotSupportedException(
        'Synthetic graphics mode is unavailable.',
      );
    }
    fixture.requests.add(mode);
    if (fixture.failWrite) {
      fixture.failWrite = false;
      throw const LegionControlCommandFailedException(
        'Synthetic graphics write failed.',
      );
    }
    fixture.selectedMode = mode;
    if (fixture.observedAfterWrite case final observation?) {
      fixture.effectiveState = observation.effective;
      fixture.expectedState = observation.expected;
    }
    fixture.writes.add(mode);
  }

  @override
  Future<void> close() async {
    if (!fixture.closed.isCompleted) fixture.closed.complete();
  }
}
