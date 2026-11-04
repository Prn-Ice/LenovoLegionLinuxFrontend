import 'package:riverbloc/riverbloc.dart';
import '../../../core/models/app_failure.dart';
import '../repository/automation_repository.dart';
import 'automation_event.dart';
import 'automation_state.dart';

class AutomationBloc extends Bloc<AutomationEvent, AutomationState> {
  AutomationBloc({required AutomationRepository repository})
    : _repository = repository,
      super(AutomationState.initial()) {
    on<AutomationEvent>((event, emit) async {
      if (_closing) return;
      switch (event) {
        case AutomationStarted():
          emit(state.copyWith(isLoading: true));
          try {
            final config = await _repository.loadConfig();
            if (_closing) return;
            emit(
              state.copyWith(config: config, hasLoaded: true, isLoading: false),
            );
          } catch (error) {
            if (_closing) return;
            emit(
              state.copyWith(
                isLoading: false,
                errorMessage: AppFailure(
                  'Could not load keyboard assignments. Retry to read your saved choices.',
                  details: '$error',
                ),
              ),
            );
          }
        case KeyboardProfileAssigned():
          if (!state.hasLoaded) return;
          final config = state.config.assign(event.mode, event.profile);
          emit(state.copyWith(isSaving: true));
          try {
            await _repository.saveConfig(config);
            if (_closing) return;
            emit(state.copyWith(config: config, isSaving: false));
          } catch (error) {
            if (_closing) return;
            emit(
              state.copyWith(
                isSaving: false,
                errorMessage: AppFailure(
                  'Could not save the keyboard assignment. Your previous choice is still in use. Try selecting the profile again.',
                  details: '$error',
                ),
              ),
            );
          }
      }
    }, transformer: (events, mapper) => events.asyncExpand(mapper));
  }

  final AutomationRepository _repository;
  bool _closing = false;

  @override
  Future<void> close() {
    _closing = true;
    return super.close();
  }
}
