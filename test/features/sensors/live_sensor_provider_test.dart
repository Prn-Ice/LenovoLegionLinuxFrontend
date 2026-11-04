import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/sensors/bloc/live_sensor_event.dart';
import 'package:legion_frontend/features/sensors/models/live_sensor_snapshot.dart';
import 'package:legion_frontend/features/sensors/providers/live_sensor_provider.dart';
import 'package:legion_frontend/features/sensors/repository/live_sensor_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverbloc/riverbloc.dart';

class _MockLiveSensorRepository extends Mock implements LiveSensorRepository {}

void main() {
  for (final fails in [false, true]) {
    testWidgets(
      'disposal during initial load prevents polling after ${fails ? 'failure' : 'success'}',
      (tester) async {
        final repository = _MockLiveSensorRepository();
        final load = Completer<LiveSensorSnapshot>();
        when(repository.loadSnapshot).thenAnswer((_) => load.future);
        final container = ProviderContainer(
          overrides: [
            liveSensorRepositoryProvider.overrideWithValue(repository),
          ],
        );
        container.listen(liveSensorBlocProvider, (_, _) {});
        final bloc = container.read(liveSensorBlocProvider.bloc);

        // Pages start the production provider's Bloc explicitly.
        bloc.add(const LiveSensorStarted());
        await tester.pump();
        verify(repository.loadSnapshot).called(1);
        expect(bloc.state.isLoading, isTrue);

        container.dispose();
        await tester.pump();
        expect(bloc.isClosed, isTrue);

        if (fails) {
          load.completeError(StateError('sensor read failed'));
        } else {
          load.complete(LiveSensorSnapshot.initial());
        }
        await tester.pump();
        // Advance beyond several production polling intervals without sleeping.
        await tester.pump(const Duration(seconds: 6));

        verifyNever(repository.loadSnapshot);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
