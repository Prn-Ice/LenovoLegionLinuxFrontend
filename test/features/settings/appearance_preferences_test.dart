import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:legion_frontend/core/theme/legion_accent.dart';
import 'package:legion_frontend/features/settings/bloc/settings_bloc.dart';
import 'package:legion_frontend/features/settings/bloc/settings_event.dart';
import 'package:legion_frontend/features/settings/bloc/settings_state.dart';
import 'package:legion_frontend/features/settings/models/appearance_theme.dart';
import 'package:legion_frontend/features/settings/models/settings_snapshot.dart';
import 'package:legion_frontend/features/settings/repository/appearance_store.dart';
import 'package:legion_frontend/features/settings/repository/settings_repository.dart';
import 'package:legion_frontend/features/settings/providers/settings_provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yaru/yaru.dart';

class MockRepository extends Mock implements SettingsRepository {}

class MockStore extends Mock implements AppearanceStore {}

void main() {
  setUpAll(() => registerFallbackValue(SettingsState.initial()));

  group('Hive appearance preferences', () {
    late Directory directory;
    late Box<dynamic> box;

    setUp(() async {
      directory = await Directory('/tmp/opencode').createTemp('appearance-');
      Hive.init(directory.path);
      box = await Hive.openBox<dynamic>('preferences');
    });

    tearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    test('round-trips all choices through a closed and reopened box', () async {
      final saved = SettingsState.initial().copyWith(
        themeMode: ThemeMode.dark,
        yaruVariant: YaruVariant.blue,
        accentFollowsPowerMode: true,
      );
      await AppearanceStore(box).save(saved);
      await box.close();
      box = await Hive.openBox<dynamic>('preferences');
      expect(AppearanceStore(box).load(), saved);
    });

    test(
      'production provider hydrates before service load and rehydrates after disposal',
      () async {
        final saved = SettingsState.initial().copyWith(
          themeMode: ThemeMode.dark,
          yaruVariant: YaruVariant.purple,
          accentFollowsPowerMode: true,
        );
        final store = AppearanceStore(box);
        await store.save(saved);
        final repository = MockRepository();
        when(
          repository.loadSnapshot,
        ).thenAnswer((_) async => const SettingsSnapshot(services: []));
        for (var launch = 0; launch < 2; launch++) {
          final container = ProviderContainer(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(repository),
              appearanceStoreProvider.overrideWithValue(store),
            ],
          );
          final subscription = container.listen(
            settingsBlocProvider,
            (_, _) {},
          );
          final bloc = container.read(settingsBlocProvider.bloc);
          expect(container.read(settingsBlocProvider), saved);
          final loaded = bloc.stream.firstWhere((s) => !s.isLoading);
          await loaded;
          expect(bloc.state.themeMode, ThemeMode.dark);
          subscription.close();
          final closed = bloc.stream.drain<void>();
          container.dispose();
          await closed;
          expect(bloc.isClosed, isTrue);
        }
      },
    );

    test(
      'missing and malformed values preserve backward-compatible defaults',
      () async {
        expect(AppearanceStore(box).load(), SettingsState.initial());
        await box.put(AppearanceStore.key, {
          'themeMode': 'future-theme',
          'yaruVariant': 42,
          'accentFollowsPowerMode': 'true',
        });
        expect(AppearanceStore(box).load(), SettingsState.initial());
        await box.put(AppearanceStore.key, {
          'themeMode': 'light',
          'yaruVariant': 'purple',
        });
        final migrated = AppearanceStore(box).load();
        expect(migrated.themeMode, ThemeMode.light);
        expect(migrated.yaruVariant, YaruVariant.purple);
        expect(migrated.accentFollowsPowerMode, isFalse);
      },
    );

    test(
      'closed storage failures are surfaced, not silently discarded',
      () async {
        final store = AppearanceStore(box);
        await box.close();
        expect(store.load, throwsA(isA<HiveError>()));
        await expectLater(
          store.save(SettingsState.initial()),
          throwsA(isA<HiveError>()),
        );
      },
    );
  });

  test(
    'hydrates immediately and serializes edits across appearance fields',
    () async {
      final repository = MockRepository();
      final store = MockStore();
      final initial = SettingsState.initial().copyWith(
        yaruVariant: YaruVariant.blue,
      );
      when(store.load).thenReturn(initial);
      final firstSave = Completer<void>();
      final writes = <SettingsState>[];
      final firstStarted = Completer<void>();
      when(() => store.save(any())).thenAnswer((invocation) async {
        writes.add(invocation.positionalArguments.single as SettingsState);
        if (writes.length == 1) {
          firstStarted.complete();
          await firstSave.future;
        }
      });
      final bloc = SettingsBloc(repository: repository, appearanceStore: store);
      addTearDown(bloc.close);
      expect(bloc.state.yaruVariant, YaruVariant.blue);
      bloc.add(const ThemeModeChanged(ThemeMode.dark));
      bloc.add(const AccentFollowsPowerModeChanged(true));
      await firstStarted.future;
      expect(writes, hasLength(1));
      final followed = bloc.stream.firstWhere((s) => s.accentFollowsPowerMode);
      firstSave.complete();
      await followed;
      expect(writes.last.themeMode, ThemeMode.dark);
      expect(writes.last.yaruVariant, YaruVariant.blue);
      final restored = bloc.stream.firstWhere((s) => !s.accentFollowsPowerMode);
      bloc.add(const AccentFollowsPowerModeChanged(false));
      await restored;
      expect(bloc.state.yaruVariant, YaruVariant.blue);
      expect(bloc.state.themeMode, ThemeMode.dark);
    },
  );

  test(
    'failed save leaves previous choices intact and can be retried',
    () async {
      final store = MockStore();
      when(store.load).thenReturn(SettingsState.initial());
      when(() => store.save(any())).thenThrow(StateError('disk full'));
      final bloc = SettingsBloc(
        repository: MockRepository(),
        appearanceStore: store,
      );
      addTearDown(bloc.close);
      final failure = bloc.stream.firstWhere(
        (s) => s.appearanceErrorMessage != null,
      );
      bloc.add(const ThemeModeChanged(ThemeMode.dark));
      await failure;
      expect(bloc.state.themeMode, ThemeMode.system);
      expect(
        bloc.state.appearanceErrorMessage,
        contains('previous appearance is unchanged'),
      );
      when(() => store.save(any())).thenAnswer((_) async {});
      final retry = bloc.stream.firstWhere(
        (s) => s.themeMode == ThemeMode.dark,
      );
      bloc.add(const ThemeModeChanged(ThemeMode.dark));
      await retry;
      expect(bloc.state.appearanceErrorMessage, isNull);
    },
  );

  test(
    'read errors remain visible after unrelated service hydration',
    () async {
      final repository = MockRepository();
      when(
        repository.loadSnapshot,
      ).thenAnswer((_) async => const SettingsSnapshot(services: []));
      final store = MockStore();
      when(store.load).thenThrow(StateError('unreadable preferences'));
      final bloc = SettingsBloc(repository: repository, appearanceStore: store);
      addTearDown(bloc.close);
      expect(
        bloc.state.appearanceErrorMessage,
        contains('Could not load appearance'),
      );
      final loaded = bloc.stream.firstWhere((s) => !s.isLoading);
      bloc.add(const SettingsStarted());
      await loaded;
      expect(
        bloc.state.appearanceErrorMessage,
        contains('Could not load appearance'),
      );
    },
  );

  test('power accent precedence covers all known and unavailable modes', () {
    final manual = SettingsState.initial().copyWith(
      yaruVariant: YaruVariant.blue,
    );
    expect(appearancePowerAccent(manual, 'performance'), isNull);
    final follow = manual.copyWith(accentFollowsPowerMode: true);
    for (final entry in {
      'quiet': LegionAccent.quiet,
      'balanced': LegionAccent.balanced,
      'performance': LegionAccent.performance,
      'balanced-performance': LegionAccent.custom,
    }.entries) {
      expect(appearancePowerAccent(follow, entry.key), entry.value);
      final themes = appearanceThemes(
        follow,
        entry.key,
        const YaruThemeData(variant: YaruVariant.blue),
      );
      // App theme resolution generates component subthemes, not just primary.
      for (final theme in [themes.theme, themes.darkTheme]) {
        expect(theme.colorScheme.primary, entry.value.color);
        expect(
          theme.textSelectionTheme.selectionColor,
          entry.value.color.withValues(alpha: 0.4),
        );
      }
    }
    for (final unknown in [null, '', 'unsupported']) {
      expect(appearancePowerAccent(follow, unknown), isNull);
      expect(follow.yaruVariant, YaruVariant.blue);
      final themes = appearanceThemes(
        follow,
        unknown,
        const YaruThemeData(variant: YaruVariant.blue),
      );
      expect(themes.theme.colorScheme.primary, YaruVariant.blue.color);
      expect(themes.darkTheme.colorScheme.primary, YaruVariant.blue.color);
    }
    expect(
      appearancePowerAccent(
        SettingsState.initial().copyWith(accentFollowsPowerMode: true),
        null,
      ),
      isNull,
    );
  });
}
