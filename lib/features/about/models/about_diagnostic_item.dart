import 'package:equatable/equatable.dart';

enum AboutDiagnosticStatus { ok, unavailable, warning, error }

class AboutDiagnosticItem extends Equatable {
  const AboutDiagnosticItem({
    required this.id,
    required this.label,
    required this.status,
    required this.value,
    this.details,
  });

  final String id;
  final String label;
  final AboutDiagnosticStatus status;
  final String value;
  final String? details;

  @override
  List<Object?> get props => [id, label, status, value, details];
}
