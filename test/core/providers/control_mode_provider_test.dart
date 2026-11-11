import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:riverbloc/riverbloc.dart';
import 'package:legion_frontend/core/models/control_mode.dart';
import 'package:legion_frontend/core/models/control_capabilities.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/core/providers/system_services_provider.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/services/legion_cli_service.dart';
import 'package:legion_frontend/core/services/portable_legion_control_transport.dart';
import 'package:legion_frontend/core/services/portable_control_launcher.dart';

import '../../support/portable_helper_process.dart';

class DeniedTransport extends LegionControlTransport {
  int closes = 0;
  final ended = Completer<void>();
  @override
  Future<ControlCapabilities> getCapabilities() async => ControlCapabilities(
    protocolVersion: 1,
    supported: [ControlCapability.interactiveControl],
  );
  @override
  Future<void> authorize() async =>
      throw const LegionControlPermissionDeniedException('denied');
  @override
  Future<void> call(String method, List<Object> arguments) async =>
      fail('write after denial');
  @override
  Future<void> close() async {
    closes++;
    if (!ended.isCompleted) ended.complete();
  }
}

void main() {
  test('installed denial never creates a portable transport', () async {
    final modes = <ControlMode>[];
    final transport = DeniedTransport();
    final container = ProviderContainer(
      overrides: [
        controlTransportFactoryProvider.overrideWithValue((mode, resolvePath) {
          modes.add(mode);
          return transport;
        }),
      ],
    );
    final client = container.read(legionControlClientProvider);
    await expectLater(
      client.setToggle(ControlToggle.hybridMode, true),
      throwsA(isA<LegionControlPermissionDeniedException>()),
    );
    expect(modes, [ControlMode.installedService]);
    container.dispose();
    await transport.ended.future;
    expect(transport.closes, 1);
  });

  test(
    'production provider disposal during CLI discovery prevents elevation',
    () async {
      final path = Completer<String>();
      final resolving = Completer<void>();
      final cli = LegionCliService(
        pathResolver: () {
          resolving.complete();
          return path.future;
        },
      );
      final process = PortableHelperProcess();
      var starts = 0;
      final launcher = PortableControlLauncher(
        executable: '/bundle/helper',
        startProcess:
            (
              _,
              _, {
              required environment,
              required workingDirectory,
              required includeParentEnvironment,
            }) async {
              starts++;
              return process;
            },
      );
      final container = ProviderContainer(
        overrides: [
          controlModeProvider.overrideWithValue(ControlMode.temporaryHelper),
          legionCliServiceProvider.overrideWith((ref) {
            ref.onDispose(cli.close);
            return cli;
          }),
          controlTransportFactoryProvider.overrideWithValue((
            mode,
            resolvePath,
          ) {
            expect(mode, ControlMode.temporaryHelper);
            return PortableLegionControlTransport(
              launcher: launcher,
              resolveCliPath: resolvePath,
              connect: (_) => DeniedTransport(),
            );
          }),
        ],
      );
      final client = container.read(legionControlClientProvider);
      final rejected = expectLater(
        client.getCapabilities(),
        throwsA(isA<LegionControlUnavailableException>()),
      );
      await resolving.future;
      container.dispose();
      await rejected;
      path.complete(portableTestCli);
      await Future<void>.delayed(Duration.zero);
      expect(starts, 0);
    },
  );
}
