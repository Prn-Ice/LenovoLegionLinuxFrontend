import 'package:equatable/equatable.dart';

import '../../../core/models/sysfs_probe.dart';

enum AboutDiagnosticStatus { ok, unavailable, warning, error }

class AboutDiagnosticItem extends Equatable {
  const AboutDiagnosticItem({
    required this.id,
    required this.label,
    required this.status,
    required this.value,
    this.details,
    this.readProbe,
    this.frontendWriteAvailable,
  });

  factory AboutDiagnosticItem.fromProbe({
    required String id,
    required String label,
    required SysfsProbe probe,
    bool? frontendWriteAvailable,
  }) => AboutDiagnosticItem(
    id: id,
    label: label,
    status: switch (probe.outcome) {
      SysfsReadOutcome.readable => AboutDiagnosticStatus.ok,
      SysfsReadOutcome.missing => AboutDiagnosticStatus.unavailable,
      SysfsReadOutcome.unreadable ||
      SysfsReadOutcome.malformed => AboutDiagnosticStatus.error,
      SysfsReadOutcome.unknown => AboutDiagnosticStatus.warning,
    },
    value:
        probe.selectedRead?.value ??
        switch (probe.outcome) {
          SysfsReadOutcome.missing => 'File missing',
          SysfsReadOutcome.unreadable => 'Could not read',
          SysfsReadOutcome.malformed => 'Invalid value',
          _ => 'Unknown',
        },
    details: [
      if (probe.selectedRead != null) probe.selectedRead!.path,
      if (probe.selectedRead == null && probe.reads.isNotEmpty)
        probe.reads
            .firstWhere(
              (read) => read.outcome != SysfsReadOutcome.missing,
              orElse: () => probe.reads.first,
            )
            .path,
      if (probe.reads.isEmpty) 'No matching hardware provider found.',
      if (frontendWriteAvailable == true)
        'The app has a write control. Writes have not been tested.',
      if (frontendWriteAvailable == false) 'The app only reads this value.',
    ].join('\n'),
    readProbe: probe,
    frontendWriteAvailable: frontendWriteAvailable,
  );

  final String id;
  final String label;
  final AboutDiagnosticStatus status;
  final String value;
  final String? details;
  final SysfsProbe? readProbe;

  /// The app has a write action. The driver and authorization are not checked.
  final bool? frontendWriteAvailable;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'status': status.name,
    'value': value,
    'details': details,
    if (readProbe != null) 'read': readProbe!.toJson(),
    'frontend_write_available': frontendWriteAvailable,
    'hardware_write_verification': 'unverified',
  };

  @override
  List<Object?> get props => [
    id,
    label,
    status,
    value,
    details,
    readProbe,
    frontendWriteAvailable,
  ];
}
