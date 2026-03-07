import 'package:equatable/equatable.dart';

class BootLogoStatus extends Equatable {
  const BootLogoStatus({
    required this.isCustomEnabled,
    required this.requiredWidth,
    required this.requiredHeight,
  });

  final bool isCustomEnabled;
  final int requiredWidth;
  final int requiredHeight;

  bool get hasDimensionConstraint => requiredWidth > 0 || requiredHeight > 0;

  String get dimensionLabel =>
      hasDimensionConstraint ? '$requiredWidth×$requiredHeight' : 'any';

  static BootLogoStatus? parseStatusOutput(String output) {
    final dimMatch = RegExp(r'dimensions: (\d+) x (\d+)').firstMatch(output);
    if (dimMatch == null) {
      return null;
    }

    return BootLogoStatus(
      isCustomEnabled: output.contains('status: ON'),
      requiredWidth: int.parse(dimMatch.group(1)!),
      requiredHeight: int.parse(dimMatch.group(2)!),
    );
  }

  @override
  List<Object?> get props => [isCustomEnabled, requiredWidth, requiredHeight];
}
