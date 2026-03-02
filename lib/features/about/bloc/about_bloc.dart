import 'package:riverbloc/riverbloc.dart';

import '../repository/about_repository.dart';
import 'about_event.dart';
import 'about_state.dart';

class AboutBloc extends Bloc<AboutEvent, AboutState> {
  AboutBloc({required AboutRepository repository})
    : _repository = repository,
      super(AboutState.initial()) {
    on<AboutStarted>(_onStarted);
    on<AboutRefreshRequested>(_onRefreshRequested);
  }

  final AboutRepository _repository;

  Future<void> _onStarted(AboutStarted event, Emitter<AboutState> emit) async {
    await _reload(emit, showLoading: true);
  }

  Future<void> _onRefreshRequested(
    AboutRefreshRequested event,
    Emitter<AboutState> emit,
  ) async {
    await _reload(emit, showLoading: true);
  }

  Future<void> _reload(
    Emitter<AboutState> emit, {
    required bool showLoading,
  }) async {
    if (showLoading) {
      emit(state.copyWith(isLoading: true, errorMessage: null));
    }

    try {
      final snapshot = await _repository.loadSnapshot();
      emit(
        state.copyWith(
          snapshot: snapshot,
          isLoading: false,
          errorMessage: null,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load diagnostics: $error',
        ),
      );
    }
  }
}
