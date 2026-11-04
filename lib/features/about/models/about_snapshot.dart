import 'package:equatable/equatable.dart';

import '../../../core/models/bridge_command_record.dart';
import 'about_diagnostic_item.dart';
import '../../lighting/models/spectrum_hid_discovery.dart';

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
    this.biosVersion,
    this.spectrumHid = const SpectrumHidDiscovery.missing(),
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
  final String? biosVersion;
  final SpectrumHidDiscovery spectrumHid;

  /// Builds the JSON copied from Diagnostics. Local CLI paths and error output
  /// stay in the UI because they can contain personal directory names.
  Map<String, Object?> toJson() => {
    'schema_version': 3,
    'updated_at': updatedAt.toIso8601String(),
    'cli_path': '<configured-cli>',
    'cli_path_exists': cliPathExists,
    'python_available': pythonAvailable,
    'control_service_active': controlServiceActive,
    'systemctl_available': systemctlAvailable,
    'cli_healthy': cliHealthy,
    'cli_health_summary': cliHealthy ? 'Healthy' : 'Unhealthy',
    'kernel_version': kernelVersion,
    'hardware_model': hardwareModel,
    'bios_version': biosVersion,
    'module_version': moduleVersion,
    'cli_version': cliVersion,
    'hardware_write_verification': 'unverified',
    'spectrum_hid': spectrumHid.toJson(),
    'diagnostics': diagnostics.map((item) => item.toJson()).toList(),
    'command_history': commandHistory
        .map(
          (record) => <String, Object?>{
            'timestamp': record.timestamp.toIso8601String(),
            'method': record.method,
            'args': record.redactedArgs,
            'is_privileged': record.isPrivileged,
            'succeeded': record.succeeded,
            'duration_ms': record.durationMs,
          },
        )
        .toList(),
  };

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
    biosVersion,
    spectrumHid,
  ];
}
