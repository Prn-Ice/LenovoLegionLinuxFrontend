import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/app_failure.dart';
import 'package:legion_frontend/core/services/legion_cli_service.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/services/legion_frontend_bridge_service.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/core/widgets/app_shell_components.dart';
import 'package:legion_frontend/features/devices/bloc/devices_bloc.dart';
import 'package:legion_frontend/features/devices/bloc/devices_event.dart';
import 'package:legion_frontend/features/devices/repository/devices_repository.dart';
import 'package:mocktail/mocktail.dart';

class _Control extends Mock implements LegionControlClient {}

class _Cli extends Mock implements LegionCliService {}

class _Sysfs extends Mock implements LegionSysfsService {}

void main() {
  testWidgets('control failure survives bridge, repository, Bloc and dialog', (
    tester,
  ) async {
    final control = _Control();
    when(() => control.authorize()).thenAnswer((_) async {});
    when(() => control.setToggle(ControlToggle.touchpad, true)).thenThrow(
      const LegionControlSetupException('Service diagnostic wording changed'),
    );
    final bloc = DevicesBloc(
      repository: DevicesRepository(
        sysfsService: _Sysfs(),
        bridgeService: LegionFrontendBridgeService(
          cliService: _Cli(),
          controlClient: control,
        ),
      ),
    );
    addTearDown(bloc.close);
    final failed = bloc.stream.firstWhere(
      (state) => state.errorMessage != null,
    );
    bloc.add(const TouchpadSetRequested(true));
    final state = await failed;
    expect(state.errorMessage?.kind, AppFailureKind.privilegeSetup);
    expect(
      state.errorMessage?.details,
      contains('Service diagnostic wording changed'),
    );
    expect(
      state.copyWith(isLoading: true).errorMessage,
      same(state.errorMessage),
    );
    expect(state.copyWith(errorMessage: null).errorMessage, isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPageBody(
            errorMessage: state.errorMessage,
            children: const [Text('Page content')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Privileged access needs setup'), findsOneWidget);
    verify(() => control.setToggle(ControlToggle.touchpad, true)).called(1);
  });
}
