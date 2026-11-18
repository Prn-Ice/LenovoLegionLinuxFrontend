import 'dart:io';

import 'package:legion_frontend/features/lighting/services/spectrum_hid_service.dart';
import 'package:legion_frontend/features/lighting/models/spectrum_led_map.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_protocol.dart';
import 'package:legion_frontend/features/lighting/models/keyboard_layout.dart';

// Run one numbered keyboard-lighting check. A frame is one set of key colors.
// These checks send colors to the keyboard; the color helpers build the data.
final _functionKeyPattern = RegExp(r'^Key: (Escape|F\d)');
final _numberKeyPattern = RegExp(r'^Key: [0-9`\-=]$');
final _letterKeyPattern = RegExp(r'^Key: [A-Z]$');

(int, int, int) _rgbFromHsv(double hue, double saturation, double value) {
  // Convert a hue wheel position to the RGB values sent to the keyboard.
  final chroma = value * saturation;
  final secondLargest = chroma * (1 - (((hue / 60) % 2) - 1).abs());
  final minimum = value - chroma;
  double red, green, blue;
  if (hue < 60) {
    (red, green, blue) = (chroma, secondLargest, 0);
  } else if (hue < 120) {
    (red, green, blue) = (secondLargest, chroma, 0);
  } else if (hue < 180) {
    (red, green, blue) = (0, chroma, secondLargest);
  } else if (hue < 240) {
    (red, green, blue) = (0, secondLargest, chroma);
  } else if (hue < 300) {
    (red, green, blue) = (secondLargest, 0, chroma);
  } else {
    (red, green, blue) = (chroma, 0, secondLargest);
  }
  return (
    ((red + minimum) * 255).round(),
    ((green + minimum) * 255).round(),
    ((blue + minimum) * 255).round(),
  );
}

SpectrumLed _spectrumLed(int ledValue, int red, int green, int blue) {
  // Match the app: adjust the color balance, then limit LED power use.
  final (balancedRed, balancedGreen, balancedBlue) = whiteBalanceRgb(
    red,
    green,
    blue,
  );
  final (cappedRed, cappedGreen, cappedBlue) = capPowerRgb(
    balancedRed,
    balancedGreen,
    balancedBlue,
  );
  return SpectrumLed(ledValue, cappedRed, cappedGreen, cappedBlue);
}

List<SpectrumLed> _solidFrame(int red, int green, int blue) => [
  for (final ledValue in kSpectrumLedValues.values)
    _spectrumLed(ledValue, red, green, blue),
];

List<SpectrumLed> _rainbowFrame([double phase = 0]) {
  final ledEntries = kSpectrumLedValues.entries.toList();
  final frame = <SpectrumLed>[];
  for (var index = 0; index < ledEntries.length; index++) {
    final (red, green, blue) = _rgbFromHsv(
      ((index / ledEntries.length) * 360 + phase) % 360,
      1,
      1,
    );
    frame.add(_spectrumLed(ledEntries[index].value, red, green, blue));
  }
  return frame;
}

List<SpectrumLed> _keyboardSectionFrame() {
  final frame = <SpectrumLed>[];
  kSpectrumLedValues.forEach((keyName, ledValue) {
    if (_functionKeyPattern.hasMatch(keyName)) {
      frame.add(_spectrumLed(ledValue, 255, 0, 0));
    } else if (_numberKeyPattern.hasMatch(keyName)) {
      frame.add(_spectrumLed(ledValue, 0, 255, 0));
    } else if (_letterKeyPattern.hasMatch(keyName)) {
      frame.add(_spectrumLed(ledValue, 0, 0, 255));
    } else if (keyName.contains('Number Pad')) {
      frame.add(_spectrumLed(ledValue, 255, 255, 255));
    } else {
      frame.add(_spectrumLed(ledValue, 25, 25, 25));
    }
  });
  return frame;
}

List<SpectrumLed> _escapeKeyFrame() => [
  for (final entry in kSpectrumLedValues.entries)
    _spectrumLed(entry.value, entry.key == 'Key: Escape' ? 255 : 0, 0, 0),
];

SpectrumLed _whiteLedAtGain(int ledValue, double gain) {
  final (red, green, blue) = capPowerRgb(255, (255 * gain).round(), 255);
  return SpectrumLed(ledValue, red, green, blue);
}

List<SpectrumLed> _whiteFrameAtGain(double gain) => [
  for (final ledValue in kSpectrumLedValues.values)
    _whiteLedAtGain(ledValue, gain),
];

List<SpectrumLed> _bandedWhiteFrame(List<double> gains) {
  final gainByKey = <String, double>{};
  for (final row in kKeyboardLayout) {
    var horizontalPosition = 0.0;
    for (final key in row.main) {
      if (!key.isGap) {
        final band =
            (((horizontalPosition + key.width / 2) / kMainUnits) * gains.length)
                .floor();
        gainByKey[key.led] =
            gains[band < gains.length ? band : gains.length - 1];
      }
      horizontalPosition += key.width;
    }
  }

  return [
    for (final entry in kSpectrumLedValues.entries)
      if (gainByKey[entry.key] case final gain?)
        _whiteLedAtGain(entry.value, gain)
      else
        SpectrumLed(entry.value, 0, 0, 0),
  ];
}

Future<void> main(List<String> args) async {
  final step = args.isNotEmpty ? (int.tryParse(args[0]) ?? 1) : 1;
  final keyboard = SpectrumHidService();
  if (!keyboard.open()) {
    stderr.writeln(
      'Could not open the Spectrum keyboard. Check the detected keyboard model '
      'and your permission to access its device file (/dev/hidraw*).',
    );
    return;
  }
  List<SpectrumLed> frame;
  var brightness = 9;
  String label;
  switch (step) {
    case 1:
      frame = _solidFrame(255, 0, 0);
      label = 'ALL RED';
    case 2:
      frame = _solidFrame(0, 255, 0);
      label = 'ALL GREEN';
    case 3:
      frame = _solidFrame(0, 0, 255);
      label = 'ALL BLUE';
    case 4:
      frame = _solidFrame(255, 255, 255);
      label = 'ALL WHITE (LED power limited)';
    case 5:
      frame = _rainbowFrame();
      label = 'PER-KEY RAINBOW';
    case 6:
      frame = _keyboardSectionFrame();
      label =
          'SECTIONS (Escape/function keys=red, numbers=green, '
          'letters=blue, number pad=white)';
    case 7:
      frame = _solidFrame(255, 255, 255);
      brightness = 3;
      label = 'DIM WHITE (brightness 3 — same white, dimmer)';
    case 8:
      frame = _escapeKeyFrame();
      label = 'SINGLE KEY (only Esc red)';
    case 9:
      frame = _bandedWhiteFrame(const [0.88, 0.92, 0.96, 1.0]);
      brightness = 3;
      label = 'DIM WHITE BANDS (left->right green: 0.88, 0.92, 0.96, 1.00)';
    case 10:
      frame = _bandedWhiteFrame(const [0.91, 0.93, 0.95, 0.97]);
      brightness = 3;
      label = 'DIM WHITE BANDS (left->right green: 0.91, 0.93, 0.95, 0.97)';
    case 11:
      frame = _whiteFrameAtGain(0.94);
      brightness = 3;
      label = 'DIM WHITE (green multiplied by 0.94)';
    case 12:
      final requestedSeconds = args.length > 1
          ? (int.tryParse(args[1]) ?? 8)
          : 8;
      final seconds = requestedSeconds.clamp(1, 120);
      final frameCount = seconds * 30;
      keyboard.setBrightness(9);
      var ok = true;
      for (var i = 0; i < frameCount; i++) {
        ok = keyboard.sendDirectFrame(_rainbowFrame(i * 2)) && ok;
        await Future<void>.delayed(const Duration(milliseconds: 33));
      }
      stdout.writeln(
        'STEP 12: ANIMATED RAINBOW '
        '($frameCount frames over ${seconds}s, sent=$ok)',
      );
      keyboard.close();
      return;
    default:
      stderr.writeln('unknown step $step');
      keyboard.close();
      return;
  }
  keyboard.setBrightness(brightness);
  final ok = keyboard.sendDirectFrame(frame);
  stdout.writeln(
    'STEP $step: $label  (${frame.length} LEDs, sent=$ok, brightness=$brightness)',
  );
  keyboard.close();
}
