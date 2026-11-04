import 'package:equatable/equatable.dart';

import 'spectrum_keyboard_profile.dart';

enum SpectrumHidDiscoveryOutcome {
  missing,
  unsupported,
  unreadable,
  malformed,
  supported,
}

extension SpectrumHidDiscoveryOutcomeJson on SpectrumHidDiscoveryOutcome {
  String get jsonName => name;
}

/// Read-only information found while looking for a supported Spectrum HID.
class SpectrumHidDiscovery extends Equatable {
  const SpectrumHidDiscovery({
    required this.outcome,
    this.vendorId,
    this.productId,
    this.selectedHidrawPath,
    this.profile,
  });

  const SpectrumHidDiscovery.missing()
    : this(outcome: SpectrumHidDiscoveryOutcome.missing);

  final SpectrumHidDiscoveryOutcome outcome;
  final int? vendorId;
  final int? productId;

  /// This is for the on-screen diagnostic only. It is deliberately redacted
  /// by AboutSnapshot.toJson because fixtures and custom roots may be private.
  final String? selectedHidrawPath;
  final SpectrumKeyboardProfile? profile;

  String? get protocol => profile?.protocol.name;

  @override
  List<Object?> get props => [
    outcome,
    vendorId,
    productId,
    selectedHidrawPath,
    profile?.vendorId,
    profile?.productId,
  ];

  Map<String, Object?> toJson() => {
    'outcome': outcome.jsonName,
    'vendor_id': vendorId == null
        ? null
        : '0x${vendorId!.toRadixString(16).padLeft(4, '0')}',
    'product_id': productId == null
        ? null
        : '0x${productId!.toRadixString(16).padLeft(4, '0')}',
    'selected_hidraw_path': selectedHidrawPath == null ? null : '<hidraw>',
    'profile': profile == null
        ? null
        : 'spectrum_${productId!.toRadixString(16).padLeft(4, '0')}',
    'protocol': protocol,
  };
}
