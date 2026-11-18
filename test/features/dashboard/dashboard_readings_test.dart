import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:legion_frontend/features/dashboard/bloc/dashboard_readings_bloc.dart';
import 'package:legion_frontend/features/dashboard/models/dashboard_metric.dart';
import 'package:legion_frontend/features/dashboard/providers/dashboard_readings_provider.dart';
import 'package:legion_frontend/features/dashboard/repository/dashboard_readings_store.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverbloc/riverbloc.dart';

class _Store extends Mock implements DashboardReadingsStore {}

void main() {
  group('saved dashboard readings', () {
    late Directory directory;
    late Box<dynamic> box;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'dashboard-preferences-',
      );
      addTearDown(() => directory.delete(recursive: true));
      addTearDown(Hive.close);
      Hive.init(directory.path);
      box = await Hive.openBox<dynamic>('preferences');
    });

    test('saves choices through the provider and restores them after reopening Hive', () async {
      await box.put('appearance', {'themeMode': 'dark'});
      final container = ProviderContainer(
        overrides: [
          dashboardReadingsStoreProvider.overrideWithValue(
            DashboardReadingsStore(box),
          ),
        ],
      );
      final subscription = container.listen(
        dashboardReadingsProvider,
        (_, _) {},
      );
      final bloc = container.read(dashboardReadingsProvider.bloc);
      final saved = bloc.stream.firstWhere(
        (s) => s.hidden.contains(DashboardMetric.igpuUsage),
      );
      bloc.add(
        const DashboardReadingChanged(
          DashboardMetric.igpuUsage,
          visible: false,
        ),
      );
      await saved;
      await container.pump();
      expect(container.read(dashboardReadingsProvider).hidden, {
        DashboardMetric.igpuUsage,
      });
      final closed = bloc.stream.drain<void>();
      subscription.close();
      container.dispose();
      await closed;
      expect(bloc.isClosed, isTrue);
      await box.close();
      box = await Hive.openBox<dynamic>('preferences');
      expect(DashboardReadingsStore(box).load(), {DashboardMetric.igpuUsage});
      expect(box.get('appearance'), {'themeMode': 'dark'});
    });

    test(
      'missing and malformed settings show readings and ignore unknown names',
      () async {
        final store = DashboardReadingsStore(box);
        expect(store.load(), isEmpty);
        await box.put(DashboardReadingsStore.key, 'invalid');
        expect(store.load(), isEmpty);
        await box.put(DashboardReadingsStore.key, [
          'futureMetric',
          'dgpuUsage',
          42,
        ]);
        expect(store.load(), {DashboardMetric.dgpuUsage});
      },
    );
  });

  test('serializes visibility edits without losing another metric', () async {
    final store = _Store();
    when(store.load).thenReturn({});
    final started = Completer<void>();
    final pending = Completer<void>();
    final writes = <Set<DashboardMetric>>[];
    when(() => store.save(any())).thenAnswer((call) async {
      writes.add(
        Set.of(call.positionalArguments.single as Set<DashboardMetric>),
      );
      if (writes.length == 1) {
        started.complete();
        await pending.future;
      }
    });
    final bloc = DashboardReadingsBloc(store: store);
    addTearDown(bloc.close);
    bloc.add(
      const DashboardReadingChanged(DashboardMetric.cpuUsage, visible: false),
    );
    bloc.add(
      const DashboardReadingChanged(DashboardMetric.igpuUsage, visible: false),
    );
    await started.future;
    expect(bloc.state.hidden, isEmpty);
    final saved = bloc.stream.firstWhere((s) => s.hidden.length == 2);
    pending.complete();
    await saved;
    expect(writes.last, {DashboardMetric.cpuUsage, DashboardMetric.igpuUsage});
  });

  test('failed save preserves choices and allows retry', () async {
    final store = _Store();
    when(store.load).thenReturn({DashboardMetric.cpuFan});
    when(() => store.save(any())).thenThrow(StateError('disk full'));
    final bloc = DashboardReadingsBloc(store: store);
    addTearDown(bloc.close);
    final failed = bloc.stream.firstWhere((s) => s.errorMessage != null);
    bloc.add(
      const DashboardReadingChanged(DashboardMetric.cpuUsage, visible: false),
    );
    await failed;
    expect(bloc.state.hidden, {DashboardMetric.cpuFan});
    when(() => store.save(any())).thenAnswer((_) async {});
    final saved = bloc.stream.firstWhere(
      (s) => s.hidden.contains(DashboardMetric.cpuUsage),
    );
    bloc.add(
      const DashboardReadingChanged(DashboardMetric.cpuUsage, visible: false),
    );
    await saved;
    expect(bloc.state.errorMessage, isNull);
  });
}
