import '../services/spectrum_protocol.dart'
    show kSpectrumGreenGain, kSpectrumMaxLedSum;
import 'keyboard_layout.dart';
import 'spectrum_led_map.dart';

/// Only this wire protocol has an implemented native transport.
enum SpectrumProtocol { gen7And8 }

/// Measurements belong to a verified keyboard, not to every ITE controller.
class SpectrumCalibration {
  const SpectrumCalibration({
    required this.maxLedSum,
    required this.dimGreenGain,
    required this.fullGreenGain,
    required this.dimBrightnessLevel,
    required this.maxBrightnessLevel,
  });

  final int maxLedSum;
  final double dimGreenGain;
  final double fullGreenGain;
  final int dimBrightnessLevel;
  final int maxBrightnessLevel;

  int brightnessLevel(int percent) =>
      (percent.clamp(0, 100) * maxBrightnessLevel / 100).round();

  double greenGainForBrightness(int percent) {
    final level = brightnessLevel(percent);
    if (level <= dimBrightnessLevel) return dimGreenGain;
    return dimGreenGain -
        ((level - dimBrightnessLevel) /
                (maxBrightnessLevel - dimBrightnessLevel)) *
            (dimGreenGain - fullGreenGain);
  }
}

/// Reviewed, built-in hardware data. There is no fallback for unknown IDs.
class SpectrumKeyboardProfile {
  const SpectrumKeyboardProfile({
    required this.vendorId,
    required this.productId,
    required this.protocol,
    required this.ledValues,
    required this.layout,
    required this.calibration,
  });

  final int vendorId;
  final int productId;
  final SpectrumProtocol protocol;
  final Map<String, int> ledValues;
  final KeyboardLayout layout;
  final SpectrumCalibration calibration;
}

const kSpectrumVendorId = 0x048D;
const kSpectrumC987ProductId = 0xC987;

/// Existing ANSI/neon map and hardware-measured calibration, unchanged.
/// The map's upstream provenance is recorded in spectrum_led_map.dart.
const kSpectrumC987Profile = SpectrumKeyboardProfile(
  vendorId: kSpectrumVendorId,
  productId: kSpectrumC987ProductId,
  protocol: SpectrumProtocol.gen7And8,
  ledValues: kSpectrumLedValues,
  layout: kLegionAnsiLayout,
  calibration: SpectrumCalibration(
    maxLedSum: kSpectrumMaxLedSum,
    dimGreenGain: 0.94,
    fullGreenGain: kSpectrumGreenGain,
    dimBrightnessLevel: 3,
    maxBrightnessLevel: 9,
  ),
);

const kSupportedSpectrumKeyboards = [kSpectrumC987Profile];

SpectrumKeyboardProfile? spectrumKeyboardProfile(int vendorId, int productId) {
  for (final profile in kSupportedSpectrumKeyboards) {
    if (profile.vendorId == vendorId && profile.productId == productId) {
      return profile;
    }
  }
  return null;
}

/// Match the entire HID_ID line; device names never establish native support.
SpectrumKeyboardProfile? spectrumKeyboardProfileFromUevent(String uevent) {
  final match = RegExp(
    r'^HID_ID=[0-9A-Fa-f]+:([0-9A-Fa-f]+):([0-9A-Fa-f]+)\r?$',
    multiLine: true,
  ).firstMatch(uevent);
  if (match == null) return null;
  final vendor = int.tryParse(match.group(1)!, radix: 16);
  final product = int.tryParse(match.group(2)!, radix: 16);
  if (vendor == null || product == null) return null;
  return spectrumKeyboardProfile(vendor, product);
}
