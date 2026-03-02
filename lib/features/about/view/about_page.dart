import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../bloc/about_event.dart';
import '../models/about_diagnostic_item.dart';
import '../models/about_snapshot.dart';
import '../providers/about_provider.dart';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aboutBlocProvider);
    final bloc = ref.read(aboutBlocProvider.bloc);
    final snapshot = state.snapshot;
    final textTheme = Theme.of(context).textTheme;

    if (state.isLoading && snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('About & Diagnostics', style: textTheme.headlineMedium),
        const SizedBox(height: 16),
        if (state.errorMessage != null) ...[
          Text(
            state.errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Frontend', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'Lenovo Legion Linux Frontend (Flutter + riverbloc)',
                ),
                const SizedBox(height: 4),
                Text('Last refresh: ${_formatTimestamp(snapshot?.updatedAt)}'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: snapshot == null
                      ? null
                      : () => _copyDiagnosticsJson(context, snapshot),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Copy diagnostics JSON'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Runtime Dependencies', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                _StatusLine(
                  label: 'CLI path',
                  value: snapshot?.cliPath ?? 'Unknown',
                  status: snapshot == null
                      ? AboutDiagnosticStatus.unavailable
                      : snapshot.cliPathExists
                      ? AboutDiagnosticStatus.ok
                      : AboutDiagnosticStatus.error,
                  details: snapshot != null && !snapshot.cliPathExists
                      ? 'CLI script was not found at this location.'
                      : null,
                ),
                _StatusLine(
                  label: 'python3',
                  value: _boolLabel(snapshot?.pythonAvailable),
                  status: _boolStatus(snapshot?.pythonAvailable),
                ),
                _StatusLine(
                  label: 'pkexec',
                  value: _boolLabel(snapshot?.pkexecAvailable),
                  status: _boolStatus(snapshot?.pkexecAvailable),
                ),
                _StatusLine(
                  label: 'systemctl',
                  value: _boolLabel(snapshot?.systemctlAvailable),
                  status: _boolStatus(snapshot?.systemctlAvailable),
                ),
                _StatusLine(
                  label: 'CLI health',
                  value: snapshot?.cliHealthSummary ?? 'Unknown',
                  status: snapshot == null
                      ? AboutDiagnosticStatus.unavailable
                      : snapshot.cliHealthy
                      ? AboutDiagnosticStatus.ok
                      : AboutDiagnosticStatus.error,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Backend Capability Probes', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                if (snapshot == null || snapshot.diagnostics.isEmpty)
                  const Text('No diagnostics available.'),
                if (snapshot != null)
                  ...snapshot.diagnostics.map(
                    (item) => _StatusLine(
                      label: item.label,
                      value: item.value,
                      status: item.status,
                      details: item.details,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: state.isLoading
              ? null
              : () => bloc.add(const AboutRefreshRequested()),
          icon: state.isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: const Text('Refresh diagnostics'),
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime? value) {
    if (value == null) {
      return 'Never';
    }
    return value.toLocal().toString();
  }

  String _boolLabel(bool? value) {
    if (value == null) {
      return 'Unknown';
    }
    return value ? 'Available' : 'Missing';
  }

  AboutDiagnosticStatus _boolStatus(bool? value) {
    if (value == null) {
      return AboutDiagnosticStatus.unavailable;
    }
    return value ? AboutDiagnosticStatus.ok : AboutDiagnosticStatus.error;
  }

  Future<void> _copyDiagnosticsJson(
    BuildContext context,
    AboutSnapshot snapshot,
  ) async {
    final payload = <String, Object?>{
      'updated_at': snapshot.updatedAt.toIso8601String(),
      'cli_path': snapshot.cliPath,
      'cli_path_exists': snapshot.cliPathExists,
      'python_available': snapshot.pythonAvailable,
      'pkexec_available': snapshot.pkexecAvailable,
      'systemctl_available': snapshot.systemctlAvailable,
      'cli_healthy': snapshot.cliHealthy,
      'cli_health_summary': snapshot.cliHealthSummary,
      'diagnostics': snapshot.diagnostics
          .map(
            (entry) => <String, Object?>{
              'id': entry.id,
              'label': entry.label,
              'status': entry.status.name,
              'value': entry.value,
              'details': entry.details,
            },
          )
          .toList(growable: false),
    };

    final text = const JsonEncoder.withIndent('  ').convert(payload);
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diagnostics JSON copied to clipboard.')),
      );
    }
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.value,
    required this.status,
    this.details,
  });

  final String label;
  final String value;
  final AboutDiagnosticStatus status;
  final String? details;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(_statusIcon(status), color: color),
      title: Text(label),
      subtitle: details == null ? null : Text(details!),
      trailing: Text(value, style: TextStyle(color: color)),
    );
  }

  Color _statusColor(BuildContext context, AboutDiagnosticStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case AboutDiagnosticStatus.ok:
        return Colors.green.shade700;
      case AboutDiagnosticStatus.warning:
        return scheme.tertiary;
      case AboutDiagnosticStatus.unavailable:
        return scheme.outline;
      case AboutDiagnosticStatus.error:
        return scheme.error;
    }
  }

  IconData _statusIcon(AboutDiagnosticStatus status) {
    switch (status) {
      case AboutDiagnosticStatus.ok:
        return Icons.check_circle_outline;
      case AboutDiagnosticStatus.warning:
        return Icons.warning_amber_outlined;
      case AboutDiagnosticStatus.unavailable:
        return Icons.help_outline;
      case AboutDiagnosticStatus.error:
        return Icons.error_outline;
    }
  }
}
