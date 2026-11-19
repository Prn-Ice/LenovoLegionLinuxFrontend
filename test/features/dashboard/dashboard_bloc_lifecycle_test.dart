import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/dashboard/bloc/dashboard_bloc.dart';
import 'package:legion_frontend/features/dashboard/bloc/dashboard_event.dart';
import 'package:legion_frontend/features/dashboard/models/dashboard_snapshot.dart';
import 'package:legion_frontend/features/dashboard/repository/dashboard_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockDashboardRepository extends Mock implements DashboardRepository {}

void main() {
  for (final fails in [false, true]) {
    test(
      'closing during an initial ${fails ? 'failed' : 'successful'} read starts no timer',
      () async {
        final repository = _MockDashboardRepository();
        final readStarted = Completer<void>();
        final pendingRead = Completer<DashboardSnapshot>();
        when(repository.loadSnapshot).thenAnswer((_) {
          readStarted.complete();
          return pendingRead.future;
        });
        final timers = <Timer>[];
        addTearDown(() {
          for (final timer in timers) {
            timer.cancel();
          }
        });
        await runZoned(
          () async {
            final bloc = DashboardBloc(repository: repository);
            bloc.add(const DashboardStarted());
            await readStarted.future;
            final closing = bloc.close();
            if (fails) {
              pendingRead.completeError(StateError('delayed read failure'));
            } else {
              pendingRead.complete(DashboardSnapshot.initial());
            }
            await closing;
          },
          zoneSpecification: ZoneSpecification(
            createPeriodicTimer: (self, parent, zone, duration, callback) {
              final timer = parent.createPeriodicTimer(
                zone,
                duration,
                callback,
              );
              timers.add(timer);
              return timer;
            },
          ),
        );
        expect(
          timers,
          isEmpty,
          reason: 'Disposal must not start periodic polling',
        );
        verify(repository.loadSnapshot).called(1);
      },
    );
  }
}
