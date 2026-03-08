// test/features/analytics/analytics_bloc_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/analytics/bloc/analytics_bloc.dart';
import 'package:legion_frontend/features/analytics/bloc/analytics_event.dart';
import 'package:legion_frontend/features/analytics/bloc/analytics_state.dart';
import 'package:legion_frontend/features/analytics/models/sensor_record.dart';
import 'package:legion_frontend/features/analytics/repository/analytics_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockAnalyticsRepository extends Mock implements AnalyticsRepository {}

void main() {
  late MockAnalyticsRepository repo;

  final fakeRecord = SensorRecord(
    timestamp: DateTime(2024),
    fan1Rpm: 3000,
    cpuTempC: 60.0,
  );

  setUp(() {
    repo = MockAnalyticsRepository();
    when(() => repo.pruneOldRecords()).thenAnswer((_) async {});
    when(() => repo.recordReading()).thenAnswer((_) async => fakeRecord);
    when(
      () => repo.readHistory(since: any(named: 'since')),
    ).thenReturn([fakeRecord]);
  });

  group('AnalyticsTicked', () {
    blocTest<AnalyticsBloc, AnalyticsState>(
      'records a reading and updates history',
      build: () => AnalyticsBloc(repository: repo),
      seed: () => AnalyticsState.initial(),
      act: (bloc) => bloc.add(const AnalyticsTicked()),
      expect: () => [
        isA<AnalyticsState>().having(
          (s) => s.history.length,
          'history length',
          greaterThan(0),
        ),
      ],
    );
  });

  group('AnalyticsWindowChanged', () {
    blocTest<AnalyticsBloc, AnalyticsState>(
      'updates the selected time window and reloads history',
      build: () => AnalyticsBloc(repository: repo),
      seed: () => AnalyticsState.initial(),
      act: (bloc) =>
          bloc.add(const AnalyticsWindowChanged(AnalyticsTimeWindow.last7d)),
      expect: () => [
        isA<AnalyticsState>().having(
          (s) => s.window,
          'window',
          AnalyticsTimeWindow.last7d,
        ),
      ],
    );
  });

  group('AnalyticsStarted', () {
    blocTest<AnalyticsBloc, AnalyticsState>(
      'prunes old records and loads history on start',
      build: () => AnalyticsBloc(repository: repo),
      act: (bloc) => bloc.add(const AnalyticsStarted()),
      verify: (_) {
        verify(() => repo.pruneOldRecords()).called(1);
        verify(() => repo.recordReading()).called(1);
      },
    );
  });
}
