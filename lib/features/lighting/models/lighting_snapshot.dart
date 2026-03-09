import 'package:equatable/equatable.dart';

class LightingSnapshot extends Equatable {
  const LightingSnapshot({
    required this.whiteKeyboardBacklightEnabled,
    required this.whiteKeyboardBacklightSupported,
    required this.yLogoLightEnabled,
    required this.yLogoLightSupported,
    required this.ioPortLightEnabled,
    required this.ioPortLightSupported,
  });

  final bool? whiteKeyboardBacklightEnabled;
  final bool whiteKeyboardBacklightSupported;
  final bool? yLogoLightEnabled;
  final bool yLogoLightSupported;
  final bool? ioPortLightEnabled;
  final bool ioPortLightSupported;

  @override
  List<Object?> get props => [
    whiteKeyboardBacklightEnabled,
    whiteKeyboardBacklightSupported,
    yLogoLightEnabled,
    yLogoLightSupported,
    ioPortLightEnabled,
    ioPortLightSupported,
  ];
}
