import 'package:equatable/equatable.dart';

class PowerMode extends Equatable {
  const PowerMode(this.value);

  factory PowerMode.fromRaw(String raw) {
    final cleaned = raw.replaceAll('[', '').replaceAll(']', '').trim();
    return PowerMode(cleaned);
  }

  final String value;

  String get label {
    switch (value) {
      case 'quiet':
        return 'Quiet';
      case 'balanced':
        return 'Balanced';
      case 'performance':
        return 'Performance';
      case 'balanced-performance':
        return 'Custom';
      default:
        return value;
    }
  }

  @override
  List<Object?> get props => [value];
}
