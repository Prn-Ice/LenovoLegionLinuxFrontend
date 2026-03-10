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

  String get description {
    switch (value) {
      case 'quiet':
        return 'Optimised for silence — fan speed minimised';
      case 'balanced':
        return 'Balanced performance and power consumption';
      case 'performance':
        return 'Maximum performance — higher fan noise and power draw';
      case 'balanced-performance':
        return 'Custom tuning (balanced-performance profile)';
      default:
        return label;
    }
  }

  @override
  List<Object?> get props => [value];
}
