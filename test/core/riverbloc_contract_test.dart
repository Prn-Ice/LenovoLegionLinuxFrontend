import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/settings/bloc/settings_event.dart';
import 'package:legion_frontend/features/settings/bloc/settings_state.dart';
import 'package:legion_frontend/features/settings/providers/settings_provider.dart';
import 'package:legion_frontend/features/settings/repository/appearance_store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverbloc/riverbloc.dart';

class MockAppearanceStore extends Mock implements AppearanceStore {}

void main() {
  setUpAll(() => registerFallbackValue(SettingsState.initial()));

  test(
    'production provider hydrates, publishes edits, and closes when unused',
    () async {
      final store = MockAppearanceStore();
      final initial = SettingsState.initial().copyWith(
        themeMode: ThemeMode.dark,
      );
      when(store.load).thenReturn(initial);
      when(() => store.save(any())).thenAnswer((_) async {});
      final container = ProviderContainer.test(
        overrides: [appearanceStoreProvider.overrideWithValue(store)],
      );
      final states = <SettingsState>[];
      final subscription = container.listen(
        settingsBlocProvider,
        (_, state) => states.add(state),
      );
      final bloc = container.read(settingsBlocProvider.bloc);
      expect(container.read(settingsBlocProvider), initial);
      final changed = bloc.stream.firstWhere(
        (state) => state.themeMode == ThemeMode.light,
      );
      bloc.add(const ThemeModeChanged(ThemeMode.light));
      await changed;
      await container.pump();
      expect(states.last.themeMode, ThemeMode.light);
      verify(store.load).called(1);
      verify(() => store.save(any())).called(1);
      final closed = bloc.stream.drain<void>();
      subscription.close();
      await container.pump();
      await closed;
      expect(bloc.isClosed, isTrue);
    },
  );

  test(
    'replacing the appearance store recreates the Bloc and publishes its state',
    () async {
      final firstStore = MockAppearanceStore();
      final nextStore = MockAppearanceStore();
      when(firstStore.load).thenReturn(SettingsState.initial());
      final nextState = SettingsState.initial().copyWith(
        themeMode: ThemeMode.dark,
      );
      when(nextStore.load).thenReturn(nextState);
      final container = ProviderContainer.test(
        overrides: [appearanceStoreProvider.overrideWithValue(firstStore)],
      );
      final states = <SettingsState>[];
      container.listen(settingsBlocProvider, (_, state) => states.add(state));
      final firstBloc = container.read(settingsBlocProvider.bloc);
      final firstClosed = firstBloc.stream.drain<void>();
      container.updateOverrides([
        appearanceStoreProvider.overrideWithValue(nextStore),
      ]);
      await container.pump();
      await firstClosed;
      expect(container.read(settingsBlocProvider.bloc), isNot(same(firstBloc)));
      expect(firstBloc.isClosed, isTrue);
      expect(container.read(settingsBlocProvider), nextState);
      expect(states.last, nextState);
      verify(nextStore.load).called(1);
    },
  );
}
