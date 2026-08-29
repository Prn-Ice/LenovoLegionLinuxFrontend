import 'dart:io';

import 'package:legion_frontend/features/lighting/services/spectrum_hid_service.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_led_map.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_protocol.dart';
import 'package:legion_frontend/features/lighting/view/keyboard_layout.dart';

final _func = RegExp(r'^Key: (Escape|F\d)');
final _num = RegExp(r'^Key: [0-9`\-=]$');
final _letter = RegExp(r'^Key: [A-Z]$');

(int, int, int) _hsv(double h, double s, double v) {
  final c = v * s;
  final x = c * (1 - (((h / 60) % 2) - 1).abs());
  final m = v - c;
  double r, g, b;
  if (h < 60) {
    (r, g, b) = (c, x, 0);
  } else if (h < 120) {
    (r, g, b) = (x, c, 0);
  } else if (h < 180) {
    (r, g, b) = (0, c, x);
  } else if (h < 240) {
    (r, g, b) = (0, x, c);
  } else if (h < 300) {
    (r, g, b) = (x, 0, c);
  } else {
    (r, g, b) = (c, 0, x);
  }
  return (
    ((r + m) * 255).round(),
    ((g + m) * 255).round(),
    ((b + m) * 255).round(),
  );
}

SpectrumLed _led(int v, int r, int g, int b) {
  // Same pipeline as the app's spectrumLedsFor: white-balance, then power-cap.
  final (wr, wg, wb) = whiteBalanceRgb(r, g, b);
  final (cr, cg, cb) = capPowerRgb(wr, wg, wb);
  return SpectrumLed(v, cr, cg, cb);
}

List<SpectrumLed> _fill(int r, int g, int b) => [
  for (final v in kSpectrumLedValues.values) _led(v, r, g, b),
];

List<SpectrumLed> _rainbow([double phase = 0]) {
  final e = kSpectrumLedValues.entries.toList();
  final out = <SpectrumLed>[];
  for (var i = 0; i < e.length; i++) {
    final (r, g, b) = _hsv(((i / e.length) * 360 + phase) % 360, 1, 1);
    out.add(_led(e[i].value, r, g, b));
  }
  return out;
}

List<SpectrumLed> _sections() {
  final out = <SpectrumLed>[];
  kSpectrumLedValues.forEach((name, v) {
    if (_func.hasMatch(name)) {
      out.add(_led(v, 255, 0, 0));
    } else if (_num.hasMatch(name)) {
      out.add(_led(v, 0, 255, 0));
    } else if (_letter.hasMatch(name)) {
      out.add(_led(v, 0, 0, 255));
    } else if (name.contains('Number Pad')) {
      out.add(_led(v, 255, 255, 255));
    } else {
      out.add(_led(v, 25, 25, 25));
    }
  });
  return out;
}

List<SpectrumLed> _escOnly() => [
  for (final e in kSpectrumLedValues.entries)
    _led(e.value, e.key == 'Key: Escape' ? 255 : 0, 0, 0),
];

SpectrumLed _whiteAtGain(int value, double gain) {
  final (r, g, b) = capPowerRgb(255, (255 * gain).round(), 255);
  return SpectrumLed(value, r, g, b);
}

List<SpectrumLed> _fillWhiteAtGain(double gain) => [
  for (final value in kSpectrumLedValues.values) _whiteAtGain(value, gain),
];

List<SpectrumLed> _dimWhiteBands(List<double> gains) {
  final gainByLed = <String, double>{};
  for (final row in kKeyboardLayout) {
    var x = 0.0;
    for (final key in row.main) {
      if (!key.isGap) {
        final band = (((x + key.width / 2) / kMainUnits) * gains.length)
            .floor();
        gainByLed[key.led] =
            gains[band < gains.length ? band : gains.length - 1];
      }
      x += key.width;
    }
  }

  return [
    for (final entry in kSpectrumLedValues.entries)
      if (gainByLed[entry.key] case final gain?)
        _whiteAtGain(entry.value, gain)
      else
        SpectrumLed(entry.value, 0, 0, 0),
  ];
}

Future<void> main(List<String> args) async {
  final step = args.isNotEmpty ? (int.tryParse(args[0]) ?? 1) : 1;
  final s = SpectrumHidService();
  if (!s.open()) {
    stderr.writeln('open FAILED — keyboard not at /dev/hidraw0?');
    return;
  }
  List<SpectrumLed> frame;
  var brightness = 9;
  String label;
  switch (step) {
    case 1:
      frame = _fill(255, 0, 0);
      label = 'ALL RED';
    case 2:
      frame = _fill(0, 255, 0);
      label = 'ALL GREEN';
    case 3:
      frame = _fill(0, 0, 255);
      label = 'ALL BLUE';
    case 4:
      frame = _fill(255, 255, 255);
      label = 'ALL WHITE (power-capped)';
    case 5:
      frame = _rainbow();
      label = 'PER-KEY RAINBOW';
    case 6:
      frame = _sections();
      label = 'SECTIONS (Fn=red, nums=green, letters=blue, numpad=white)';
    case 7:
      frame = _fill(255, 255, 255);
      brightness = 3;
      label = 'DIM WHITE (brightness 3 — same white, dimmer)';
    case 8:
      frame = _escOnly();
      label = 'SINGLE KEY (only Esc red)';
    case 9:
      frame = _dimWhiteBands(const [0.88, 0.92, 0.96, 1.0]);
      brightness = 3;
      label = 'DIM WHITE BANDS (left->right green: 0.88, 0.92, 0.96, 1.00)';
    case 10:
      frame = _dimWhiteBands(const [0.91, 0.93, 0.95, 0.97]);
      brightness = 3;
      label = 'DIM WHITE BANDS (left->right green: 0.91, 0.93, 0.95, 0.97)';
    case 11:
      frame = _fillWhiteAtGain(0.94);
      brightness = 3;
      label = 'ADAPTIVE DIM WHITE (green: 0.94)';
    case 12:
      final requestedSeconds = args.length > 1
          ? (int.tryParse(args[1]) ?? 8)
          : 8;
      final seconds = requestedSeconds.clamp(1, 120);
      final frameCount = seconds * 30;
      s.setBrightness(9);
      var ok = true;
      for (var i = 0; i < frameCount; i++) {
        ok = s.sendDirectFrame(_rainbow(i * 2)) && ok;
        await Future<void>.delayed(const Duration(milliseconds: 33));
      }
      stdout.writeln(
        'STEP 12: ANIMATED RAINBOW '
        '($frameCount frames over ${seconds}s, sent=$ok)',
      );
      s.close();
      return;
    default:
      stderr.writeln('unknown step $step');
      s.close();
      return;
  }
  s.setBrightness(brightness);
  final ok = s.sendDirectFrame(frame);
  stdout.writeln(
    'STEP $step: $label  (${frame.length} LEDs, sent=$ok, brightness=$brightness)',
  );
  s.close();
}
