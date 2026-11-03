import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/settings/bloc/settings_state.dart';
import 'package:legion_frontend/features/settings/models/service_control.dart';
import 'package:legion_frontend/features/settings/models/settings_snapshot.dart';
import 'package:legion_frontend/features/settings/providers/settings_provider.dart';
import 'package:legion_frontend/features/settings/repository/settings_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverbloc/riverbloc.dart';

class MockSettingsRepository extends Mock implements SettingsRepository {}

const service = ServiceControl(
  id: 'power_profiles_daemon',
  label: 'power-profiles-daemon',
  units: ['power-profiles-daemon'],
  supported: true,
  active: true,
  enabled: true,
);

void main() {
  test(
    'production provider loads settings and closes its Bloc when unused',
    () async {
      final repository = MockSettingsRepository();
      final load = Completer<SettingsSnapshot>();
      when(repository.loadSnapshot).thenAnswer((_) => load.future);
      final container = ProviderContainer.test(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      final subscription = container.listen(settingsBlocProvider, (_, _) {});
      final bloc = container.read(settingsBlocProvider.bloc);
      final loaded = bloc.stream.firstWhere((state) => state.hasLoaded);

      load.complete(const SettingsSnapshot(services: [service]));
      await loaded;
      await container.pump();

      expect(container.read(settingsBlocProvider).services, [service]);
      verify(repository.loadSnapshot).called(1);

      final closed = bloc.stream.drain<void>();
      subscription.close();
      await container.pump();
      await closed;
      expect(bloc.isClosed, isTrue);
    },
  );

  test(
    'replacing the repository recreates the Bloc and publishes its state',
    () async {
      final firstRepository = MockSettingsRepository();
      final nextRepository = MockSettingsRepository();
      final firstLoad = Completer<SettingsSnapshot>();
      final nextLoad = Completer<SettingsSnapshot>();
      when(firstRepository.loadSnapshot).thenAnswer((_) => firstLoad.future);
      when(nextRepository.loadSnapshot).thenAnswer((_) => nextLoad.future);
      final container = ProviderContainer.test(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(firstRepository),
        ],
      );
      final states = <SettingsState>[];
      container.listen(settingsBlocProvider, (_, state) => states.add(state));
      final firstBloc = container.read(settingsBlocProvider.bloc);
      final firstLoaded = firstBloc.stream.firstWhere(
        (state) => state.hasLoaded,
      );
      firstLoad.complete(const SettingsSnapshot(services: [service]));
      await firstLoaded;

      final firstClosed = firstBloc.stream.drain<void>();
      container.updateOverrides([
        settingsRepositoryProvider.overrideWithValue(nextRepository),
      ]);
      await container.pump();
      final nextBloc = container.read(settingsBlocProvider.bloc);
      expect(nextBloc, isNot(same(firstBloc)));
      await firstClosed;
      expect(firstBloc.isClosed, isTrue);

      final nextLoaded = nextBloc.stream.firstWhere((state) => state.hasLoaded);
      final disabledService = service.copyWith(enabled: false);
      nextLoad.complete(SettingsSnapshot(services: [disabledService]));
      await nextLoaded;
      await container.pump();

      expect(container.read(settingsBlocProvider).services, [disabledService]);
      expect(states.last.services, [disabledService]);
      verify(nextRepository.loadSnapshot).called(1);
    },
  );
}
