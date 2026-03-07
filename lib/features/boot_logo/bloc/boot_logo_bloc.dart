import 'package:riverbloc/riverbloc.dart';

import '../repository/boot_logo_repository.dart';
import 'boot_logo_event.dart';
import 'boot_logo_state.dart';

const _acceptedExtensions = {'.png', '.jpg', '.jpeg', '.bmp'};

class BootLogoBloc extends Bloc<BootLogoEvent, BootLogoState> {
  BootLogoBloc({required BootLogoRepository repository})
    : _repository = repository,
      super(BootLogoState.initial()) {
    on<BootLogoStarted>(_onStarted);
    on<BootLogoFileSelected>(_onFileSelected);
    on<BootLogoApplyRequested>(_onApplyRequested);
    on<BootLogoRestoreRequested>(_onRestoreRequested);
    on<BootLogoRefreshRequested>(_onRefreshRequested);
  }

  final BootLogoRepository _repository;

  Future<void> _onStarted(
    BootLogoStarted event,
    Emitter<BootLogoState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    await _reloadState(emit);
  }

  Future<void> _onRefreshRequested(
    BootLogoRefreshRequested event,
    Emitter<BootLogoState> emit,
  ) async {
    await _reloadState(emit);
  }

  void _onFileSelected(
    BootLogoFileSelected event,
    Emitter<BootLogoState> emit,
  ) {
    final path = event.imagePath;
    if (path.isEmpty) {
      emit(
        state.copyWith(
          selectedImagePath: null,
          validationError: null,
          errorMessage: null,
          noticeMessage: null,
        ),
      );
      return;
    }

    final ext = path.contains('.') ? '.${path.split('.').last.toLowerCase()}' : '';
    final validationError = _acceptedExtensions.contains(ext)
        ? null
        : 'Unsupported format "$ext". Use PNG, JPEG, or BMP.';

    emit(
      state.copyWith(
        selectedImagePath: path,
        validationError: validationError,
        errorMessage: null,
        noticeMessage: null,
      ),
    );
  }

  Future<void> _onApplyRequested(
    BootLogoApplyRequested event,
    Emitter<BootLogoState> emit,
  ) async {
    final imagePath = state.selectedImagePath;
    if (imagePath == null || !state.canApply) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await _repository.enableBootLogo(imagePath);
      await _reloadState(emit, noticeMessage: 'Boot logo applied successfully.');
    } on BootLogoRepositoryException catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: error.message));
    }
  }

  Future<void> _onRestoreRequested(
    BootLogoRestoreRequested event,
    Emitter<BootLogoState> emit,
  ) async {
    if (state.isApplying) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await _repository.restoreBootLogo();
      await _reloadState(emit, noticeMessage: 'Boot logo restored to default.');
    } on BootLogoRepositoryException catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: error.message));
    }
  }

  Future<void> _reloadState(
    Emitter<BootLogoState> emit, {
    String? noticeMessage,
  }) async {
    try {
      final snapshot = await _repository.loadSnapshot();
      emit(
        state.copyWith(
          status: snapshot.status,
          isLoading: false,
          isApplying: false,
          noticeMessage: noticeMessage,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isLoading: false,
          isApplying: false,
          errorMessage: 'Failed to load boot logo status: $error',
        ),
      );
    }
  }
}
