import 'package:equatable/equatable.dart';

import '../../../core/models/bridge_command_record.dart';
import 'about_diagnostic_item.dart';

class AboutSnapshot extends Equatable {
  const AboutSnapshot({
    required this.updatedAt,
    required this.cliPath,
    required this.cliPathExists,
    required this.pythonAvailable,
    required this.controlServiceActive,
    required this.systemctlAvailable,
    required this.cliHealthy,
    required this.cliHealthSummary,
    required this.diagnostics,
    required this.kernelVersion,
    required this.hardwareModel,
    required this.moduleVersion,
    required this.cliVersion,
    required this.commandHistory,
  });

  final DateTime updatedAt;
  final String cliPath;
  final bool cliPathExists;
  final bool pythonAvailable;
  final bool controlServiceActive;
  final bool systemctlAvailable;
  final bool cliHealthy;
  final String cliHealthSummary;
  final List<AboutDiagnosticItem> diagnostics;
  final String? kernelVersion;
  final String? hardwareModel;
  final String? moduleVersion;
  final String? cliVersion;
  final List<BridgeCommandRecord> commandHistory;

  @override
  List<Object?> get props => [
    updatedAt,
    cliPath,
    cliPathExists,
    pythonAvailable,
    controlServiceActive,
    systemctlAvailable,
    cliHealthy,
    cliHealthSummary,
    diagnostics,
    kernelVersion,
    hardwareModel,
    moduleVersion,
    cliVersion,
    commandHistory,
  ];
}
