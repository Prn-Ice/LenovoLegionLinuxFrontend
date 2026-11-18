import 'package:equatable/equatable.dart';
import 'package:riverbloc/riverbloc.dart';

import '../models/dashboard_metric.dart';
import '../repository/dashboard_readings_store.dart';

class DashboardReadingChanged extends Equatable {
  const DashboardReadingChanged(this.metric, {required this.visible});

  final DashboardMetric metric;
  final bool visible;

  @override
  List<Object?> get props => [metric, visible];
}

class DashboardReadingsState extends Equatable {
  DashboardReadingsState({
    Set<DashboardMetric> hidden = const {},
    this.errorMessage,
  }) : hidden = Set.unmodifiable(hidden);

  final Set<DashboardMetric> hidden;
  final String? errorMessage;

  @override
  List<Object?> get props => [hidden, errorMessage];
}

class DashboardReadingsBloc
    extends Bloc<DashboardReadingChanged, DashboardReadingsState> {
  DashboardReadingsBloc({DashboardReadingsStore? store})
    : _store = store,
      super(_load(store)) {
    on<DashboardReadingChanged>(
      _changeReading,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
  }

  final DashboardReadingsStore? _store;

  static DashboardReadingsState _load(DashboardReadingsStore? store) {
    try {
      return DashboardReadingsState(hidden: store?.load() ?? {});
    } catch (error) {
      return DashboardReadingsState(
        errorMessage:
            'Could not load dashboard preferences. All available '
            'readings are shown. Check that your application data is readable, '
            'then restart the app. Technical details: $error',
      );
    }
  }

  Future<void> _changeReading(
    DashboardReadingChanged event,
    Emitter<DashboardReadingsState> emit,
  ) async {
    final hidden = {...state.hidden};
    if (event.visible) {
      hidden.remove(event.metric);
    } else {
      hidden.add(event.metric);
    }
    emit(DashboardReadingsState(hidden: state.hidden));
    try {
      await _store?.save(hidden);
      if (emit.isDone) return;
      emit(DashboardReadingsState(hidden: hidden));
    } catch (error) {
      if (emit.isDone) return;
      emit(
        DashboardReadingsState(
          hidden: state.hidden,
          errorMessage:
              'Could not save dashboard preferences. Your previous '
              'choices are unchanged. Check free disk space and that your '
              'application data is writable, then try again. Technical details: $error',
        ),
      );
    }
  }
}
