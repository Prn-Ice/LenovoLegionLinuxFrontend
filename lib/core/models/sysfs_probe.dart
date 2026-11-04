import 'package:equatable/equatable.dart';

import 'hardware_check.dart';

class HardwareFileResults {
  const HardwareFileResults({
    required this.checks,
    required this.sensorProviders,
  });

  final Map<HardwareCheck, SysfsProbe> checks;
  final List<SysfsProbe> sensorProviders;
}

enum SysfsReadOutcome { readable, missing, unreadable, malformed, unknown }

/// The result of reading one hardware file. Invalid values are not saved.
class SysfsRead extends Equatable {
  const SysfsRead({required this.path, required this.outcome, this.value});

  final String path;
  final SysfsReadOutcome outcome;
  final String? value;

  Map<String, Object?> toJson() => {
    'path': path,
    'outcome': outcome.name,
    if (value != null) 'value': value,
  };

  @override
  List<Object?> get props => [path, outcome, value];
}

/// Files checked, in the order used by the frontend's hardware reader.
class SysfsProbe extends Equatable {
  const SysfsProbe(this.reads);

  final List<SysfsRead> reads;

  SysfsRead? get selectedRead {
    for (final read in reads) {
      if (read.outcome == SysfsReadOutcome.readable) return read;
    }
    return null;
  }

  SysfsReadOutcome get outcome {
    if (selectedRead != null) return SysfsReadOutcome.readable;
    for (final read in reads) {
      if (read.outcome != SysfsReadOutcome.missing) return read.outcome;
    }
    return reads.isEmpty ? SysfsReadOutcome.unknown : SysfsReadOutcome.missing;
  }

  Map<String, Object?> toJson() => {
    'outcome': outcome.name,
    'selected_path': selectedRead?.path,
    'attempts': reads.map((read) => read.toJson()).toList(),
  };

  @override
  List<Object?> get props => [reads];
}
