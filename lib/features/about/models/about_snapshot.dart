import 'package:equatable/equatable.dart';

import 'about_diagnostic_item.dart';

class AboutSnapshot extends Equatable {
  const AboutSnapshot({
    required this.updatedAt,
    required this.cliPath,
    required this.cliPathExists,
    required this.pythonAvailable,
    required this.pkexecAvailable,
    required this.systemctlAvailable,
    required this.cliHealthy,
    required this.cliHealthSummary,
    required this.diagnostics,
  });

  final DateTime updatedAt;
  final String cliPath;
  final bool cliPathExists;
  final bool pythonAvailable;
  final bool pkexecAvailable;
  final bool systemctlAvailable;
  final bool cliHealthy;
  final String cliHealthSummary;
  final List<AboutDiagnosticItem> diagnostics;

  @override
  List<Object?> get props => [
    updatedAt,
    cliPath,
    cliPathExists,
    pythonAvailable,
    pkexecAvailable,
    systemctlAvailable,
    cliHealthy,
    cliHealthSummary,
    diagnostics,
  ];
}
