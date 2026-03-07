import 'package:equatable/equatable.dart';

import '../models/boot_logo_status.dart';

class BootLogoState extends Equatable {
  const BootLogoState({
    required this.status,
    required this.selectedImagePath,
    required this.validationError,
    required this.isLoading,
    required this.isApplying,
    required this.errorMessage,
    required this.noticeMessage,
  });

  factory BootLogoState.initial() => const BootLogoState(
    status: null,
    selectedImagePath: null,
    validationError: null,
    isLoading: false,
    isApplying: false,
    errorMessage: null,
    noticeMessage: null,
  );

  static const _unset = Object();

  final BootLogoStatus? status;
  final String? selectedImagePath;
  final String? validationError;
  final bool isLoading;
  final bool isApplying;
  final String? errorMessage;
  final String? noticeMessage;

  bool get canApply =>
      selectedImagePath != null && validationError == null && !isApplying;

  BootLogoState copyWith({
    Object? status = _unset,
    Object? selectedImagePath = _unset,
    Object? validationError = _unset,
    bool? isLoading,
    bool? isApplying,
    Object? errorMessage = _unset,
    Object? noticeMessage = _unset,
  }) {
    return BootLogoState(
      status: status == _unset ? this.status : status as BootLogoStatus?,
      selectedImagePath: selectedImagePath == _unset
          ? this.selectedImagePath
          : selectedImagePath as String?,
      validationError: validationError == _unset
          ? this.validationError
          : validationError as String?,
      isLoading: isLoading ?? this.isLoading,
      isApplying: isApplying ?? this.isApplying,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
      noticeMessage: noticeMessage == _unset
          ? this.noticeMessage
          : noticeMessage as String?,
    );
  }

  @override
  List<Object?> get props => [
    status,
    selectedImagePath,
    validationError,
    isLoading,
    isApplying,
    errorMessage,
    noticeMessage,
  ];
}
