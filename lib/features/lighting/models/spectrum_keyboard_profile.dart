import '../services/spectrum_protocol.dart'
    show kSpectrumGreenGain, kSpectrumMaxLedSum;
import 'keyboard_layout.dart';
import 'spectrum_led_map.dart';

/// Packet format used to send colors to the keyboard. We support Gen 7/8.
enum SpectrumProtocol { gen7And8 }

/// Numbers used to adjust green brightness and limit each LED's total RGB
/// output, based on measurements from the keyboard.
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

/// USB IDs select the keyboard. The map says which LED each key controls;
/// the layout places keys in the preview, and calibration adjusts their colors.
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

/// LED addresses came from OpenRGB's Gen 7/8 ANSI and neon tables; see
/// spectrum_led_map.dart. Measurements on the c987 keyboard supplied the green
/// brightness adjustments (0.94 when dim, 0.88 at full brightness) and the
/// 720 total RGB limit. We use these numbers to keep white neutral and lit.
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

/// Looks up the keyboard by its USB IDs. Unsupported IDs return null.
SpectrumKeyboardProfile? spectrumKeyboardProfile(int vendorId, int productId) {
  for (final profile in kSupportedSpectrumKeyboards) {
    if (profile.vendorId == vendorId && profile.productId == productId) {
      return profile;
    }
  }
  return null;
}

/// Reads the USB IDs from Linux's HID_ID line and looks up the keyboard.
SpectrumKeyboardProfile? spectrumKeyboardProfileFromUevent(String uevent) {
  final identity = spectrumHidIdentityFromUevent(uevent);
  return identity == null
      ? null
      : spectrumKeyboardProfile(identity.vendorId, identity.productId);
}

class SpectrumHidIdentity {
  const SpectrumHidIdentity(this.vendorId, this.productId);
  final int vendorId;
  final int productId;
}

SpectrumHidIdentity? spectrumHidIdentityFromUevent(String uevent) {
  final match = RegExp(
    r'^HID_ID=[0-9A-Fa-f]+:([0-9A-Fa-f]+):([0-9A-Fa-f]+)\r?$',
    multiLine: true,
  ).firstMatch(uevent);
  if (match == null) return null;
  final vendor = int.tryParse(match.group(1)!, radix: 16);
  final product = int.tryParse(match.group(2)!, radix: 16);
  if (vendor == null || product == null) return null;
  return SpectrumHidIdentity(vendor, product);
}
