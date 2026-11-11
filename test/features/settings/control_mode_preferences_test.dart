import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:legion_frontend/core/models/control_mode.dart';
import 'package:legion_frontend/features/settings/bloc/settings_bloc.dart';
import 'package:legion_frontend/features/settings/bloc/settings_event.dart';
import 'package:legion_frontend/features/settings/repository/control_mode_store.dart';
import 'package:legion_frontend/features/settings/repository/settings_repository.dart';
import 'package:mocktail/mocktail.dart';

class Repository extends Mock implements SettingsRepository {}

class Store extends Mock implements ControlModeStore {}

void main() {
  test(
    'hardware access preference survives a closed and reopened box',
    () async {
      final directory = await Directory.systemTemp.createTemp('control-mode-');
      addTearDown(() => directory.delete(recursive: true));
      addTearDown(Hive.close);
      Hive.init(directory.path);
      var box = await Hive.openBox<dynamic>('preferences');
      expect(ControlModeStore(box).load(), ControlMode.installedService);
      await ControlModeStore(box).save(ControlMode.temporaryHelper);
      await box.close();
      box = await Hive.openBox<dynamic>('preferences');
      expect(ControlModeStore(box).load(), ControlMode.temporaryHelper);
    },
  );

  test(
    'selection changes after saving without changing the active session',
    () async {
      final store = Store();
      final saved = Completer<void>();
      when(store.load).thenReturn(ControlMode.installedService);
      when(
        () => store.save(ControlMode.temporaryHelper),
      ).thenAnswer((_) => saved.future);
      final bloc = SettingsBloc(
        repository: Repository(),
        controlModeStore: store,
        activeControlMode: ControlMode.installedService,
        portableControlAvailable: true,
      );
      addTearDown(bloc.close);
      final saving = bloc.stream.firstWhere(
        (state) => state.isSavingControlMode,
      );
      bloc.add(const ControlModeChanged(ControlMode.temporaryHelper));
      await saving;
      expect(bloc.state.nextControlMode, ControlMode.installedService);
      final updated = bloc.stream.firstWhere(
        (state) => state.nextControlMode == ControlMode.temporaryHelper,
      );
      saved.complete();
      await updated;
      expect(bloc.state.activeControlMode, ControlMode.installedService);
    },
  );

  test(
    'acknowledges only the displayed failure so a repeat can be shown',
    () async {
      final store = Store();
      when(store.load).thenReturn(ControlMode.installedService);
      when(
        () => store.save(ControlMode.temporaryHelper),
      ).thenThrow(StateError('disk full'));
      final bloc = SettingsBloc(
        repository: Repository(),
        controlModeStore: store,
        portableControlAvailable: true,
      );
      addTearDown(bloc.close);
      final failed = bloc.stream.firstWhere(
        (state) => state.controlModeErrorMessage != null,
      );
      bloc.add(const ControlModeChanged(ControlMode.temporaryHelper));
      final first = (await failed).controlModeErrorMessage!;
      final acknowledged = bloc.stream.firstWhere(
        (state) => state.controlModeErrorMessage == null,
      );
      bloc.add(ControlModeErrorDismissed(first));
      await acknowledged;
      final repeated = bloc.stream.firstWhere(
        (state) => state.controlModeErrorMessage != null,
      );
      bloc.add(const ControlModeChanged(ControlMode.temporaryHelper));
      final next = (await repeated).controlModeErrorMessage;
      bloc.add(ControlModeErrorDismissed(first));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.controlModeErrorMessage, same(next));
    },
  );
  test('failed save preserves the previous selection', () async {
    final store = Store();
    when(store.load).thenReturn(ControlMode.installedService);
    when(
      () => store.save(ControlMode.temporaryHelper),
    ).thenThrow(StateError('disk full'));
    final bloc = SettingsBloc(
      repository: Repository(),
      controlModeStore: store,
      portableControlAvailable: true,
    );
    addTearDown(bloc.close);
    final failed = bloc.stream.firstWhere(
      (state) => state.controlModeErrorMessage != null,
    );
    bloc.add(const ControlModeChanged(ControlMode.temporaryHelper));
    await failed;
    expect(bloc.state.nextControlMode, ControlMode.installedService);
    expect(bloc.state.isSavingControlMode, isFalse);
  });
}
