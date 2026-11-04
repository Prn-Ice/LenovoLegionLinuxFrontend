import 'package:equatable/equatable.dart';

import 'spectrum_keyboard_profile.dart';

enum SpectrumHidDiscoveryOutcome {
  missing,
  rootMissing,
  rootUnreadable,
  unknown,
  unsupported,
  unreadable,
  malformed,
  malformedUtf8,
  supported,
}

class SpectrumHidAttempt extends Equatable {
  const SpectrumHidAttempt({
    required this.hidrawName,
    required this.outcome,
    this.vendorId,
    this.productId,
  });

  final String hidrawName;
  final SpectrumHidDiscoveryOutcome outcome;
  final int? vendorId;
  final int? productId;

  Map<String, Object?> toJson() => {
    'hidraw': hidrawName,
    'outcome': outcome.name,
    'vendor_id': vendorId == null ? null : _hex(vendorId!),
    'product_id': productId == null ? null : _hex(productId!),
  };

  @override
  List<Object?> get props => [hidrawName, outcome, vendorId, productId];
}

/// Read-only information found while looking for a supported Spectrum HID.
class SpectrumHidDiscovery extends Equatable {
  const SpectrumHidDiscovery({
    required this.outcome,
    this.vendorId,
    this.productId,
    this.selectedHidrawPath,
    this.profile,
    this.attempts = const [],
  });

  const SpectrumHidDiscovery.missing()
    : this(outcome: SpectrumHidDiscoveryOutcome.missing);

  final SpectrumHidDiscoveryOutcome outcome;
  final int? vendorId;
  final int? productId;

  /// The device path used by the service. JSON hides custom directory names.
  final String? selectedHidrawPath;
  final SpectrumKeyboardProfile? profile;
  final List<SpectrumHidAttempt> attempts;

  SpectrumProtocol? get protocol => profile?.protocol;

  String? get _exportPath {
    final path = selectedHidrawPath;
    if (path == null) return null;
    if (RegExp(r'^/dev/hidraw[0-9]+$').hasMatch(path)) return path;
    final name = path.split('/').last;
    return RegExp(r'^hidraw[0-9]+$').hasMatch(name)
        ? '<custom-dev-root>/$name'
        : '<custom-dev-root>/hidraw';
  }

  @override
  List<Object?> get props => [
    outcome,
    vendorId,
    productId,
    selectedHidrawPath,
    profile?.vendorId,
    profile?.productId,
    attempts,
  ];

  Map<String, Object?> toJson() => {
    'outcome': outcome.name,
    'vendor_id': vendorId == null
        ? null
        : '0x${vendorId!.toRadixString(16).padLeft(4, '0')}',
    'product_id': productId == null
        ? null
        : '0x${productId!.toRadixString(16).padLeft(4, '0')}',
    'selected_hidraw_path': _exportPath,
    'profile': profile == null
        ? null
        : 'spectrum_${profile!.productId.toRadixString(16).padLeft(4, '0')}',
    'protocol': protocol?.name,
    'attempts': attempts.map((attempt) => attempt.toJson()).toList(),
  };
}

String _hex(int value) => '0x${value.toRadixString(16).padLeft(4, '0')}';
