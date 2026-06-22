/// A single key in the visual keyboard layout. [led] is the exact OpenRGB LED
/// name (matched against `OpenRgbDevice.leds`); [label] is the short cap text;
/// [width] is in key units. A gap has an empty [led].
class KeyCap {
  const KeyCap(this.led, this.label, {this.width = 1});
  const KeyCap.gap(this.width) : led = '', label = '';

  final String led;
  final String label;
  final double width;

  bool get isGap => led.isEmpty;
}

/// A keyboard row split into three column groups with fixed widths, so the
/// nav cluster and numpad line up vertically across every row.
class KeyRow {
  const KeyRow({
    this.main = const [],
    this.nav = const [],
    this.numpad = const [],
  });

  final List<KeyCap> main;
  final List<KeyCap> nav;
  final List<KeyCap> numpad;
}

// Fixed column-group widths (key units). Each row's group content must fit.
const double kMainUnits = 15;
const double kNavUnits = 3;
const double kNumpadUnits = 4;
const double kGroupGap = 0.5;

/// Approximate physical layout of the Legion keyboard. Names must match the
/// OpenRGB LED names; unmatched keys render non-paintable.
const List<KeyRow> kKeyboardLayout = [
  // Function row
  KeyRow(
    main: [
      KeyCap('Key: Escape', 'Esc'),
      KeyCap.gap(0.6),
      KeyCap('Key: F1', 'F1'),
      KeyCap('Key: F2', 'F2'),
      KeyCap('Key: F3', 'F3'),
      KeyCap('Key: F4', 'F4'),
      KeyCap.gap(0.4),
      KeyCap('Key: F5', 'F5'),
      KeyCap('Key: F6', 'F6'),
      KeyCap('Key: F7', 'F7'),
      KeyCap('Key: F8', 'F8'),
      KeyCap.gap(0.4),
      KeyCap('Key: F9', 'F9'),
      KeyCap('Key: F10', 'F10'),
      KeyCap('Key: F11', 'F11'),
      KeyCap('Key: F12', 'F12'),
    ],
    nav: [KeyCap('Key: Print Screen', 'Prt')],
  ),
  // Number row
  KeyRow(
    main: [
      KeyCap('Key: `', '`'),
      KeyCap('Key: 1', '1'),
      KeyCap('Key: 2', '2'),
      KeyCap('Key: 3', '3'),
      KeyCap('Key: 4', '4'),
      KeyCap('Key: 5', '5'),
      KeyCap('Key: 6', '6'),
      KeyCap('Key: 7', '7'),
      KeyCap('Key: 8', '8'),
      KeyCap('Key: 9', '9'),
      KeyCap('Key: 0', '0'),
      KeyCap('Key: -', '-'),
      KeyCap('Key: =', '='),
      KeyCap('Key: Backspace', 'Bksp', width: 2),
    ],
    nav: [
      KeyCap('Key: Insert', 'Ins'),
      KeyCap('Key: Home', 'Hom'),
      KeyCap('Key: Page Up', 'PgU'),
    ],
    numpad: [
      KeyCap('Key: Num Lock', 'Num'),
      KeyCap('Key: Number Pad /', '/'),
      KeyCap('Key: Number Pad *', '*'),
      KeyCap('Key: Number Pad -', '-'),
    ],
  ),
  // Tab row
  KeyRow(
    main: [
      KeyCap('Key: Tab', 'Tab', width: 1.5),
      KeyCap('Key: Q', 'Q'),
      KeyCap('Key: W', 'W'),
      KeyCap('Key: E', 'E'),
      KeyCap('Key: R', 'R'),
      KeyCap('Key: T', 'T'),
      KeyCap('Key: Y', 'Y'),
      KeyCap('Key: U', 'U'),
      KeyCap('Key: I', 'I'),
      KeyCap('Key: O', 'O'),
      KeyCap('Key: P', 'P'),
      KeyCap('Key: [', '['),
      KeyCap('Key: ]', ']'),
      KeyCap('Key: \\ (ANSI)', '\\', width: 1.5),
    ],
    nav: [
      KeyCap('Key: Delete', 'Del'),
      KeyCap('Key: End', 'End'),
      KeyCap('Key: Page Down', 'PgD'),
    ],
    numpad: [
      KeyCap('Key: Number Pad 7', '7'),
      KeyCap('Key: Number Pad 8', '8'),
      KeyCap('Key: Number Pad 9', '9'),
      KeyCap('Key: Number Pad +', '+'),
    ],
  ),
  // Caps row
  KeyRow(
    main: [
      KeyCap('Key: Caps Lock', 'Caps', width: 1.75),
      KeyCap('Key: A', 'A'),
      KeyCap('Key: S', 'S'),
      KeyCap('Key: D', 'D'),
      KeyCap('Key: F', 'F'),
      KeyCap('Key: G', 'G'),
      KeyCap('Key: H', 'H'),
      KeyCap('Key: J', 'J'),
      KeyCap('Key: K', 'K'),
      KeyCap('Key: L', 'L'),
      KeyCap('Key: ;', ';'),
      KeyCap("Key: '", "'"),
      KeyCap('Key: Enter', 'Enter', width: 2.25),
    ],
    numpad: [
      KeyCap('Key: Number Pad 4', '4'),
      KeyCap('Key: Number Pad 5', '5'),
      KeyCap('Key: Number Pad 6', '6'),
    ],
  ),
  // Shift row
  KeyRow(
    main: [
      KeyCap('Key: Left Shift', 'Shift', width: 2.25),
      KeyCap('Key: Z', 'Z'),
      KeyCap('Key: X', 'X'),
      KeyCap('Key: C', 'C'),
      KeyCap('Key: V', 'V'),
      KeyCap('Key: B', 'B'),
      KeyCap('Key: N', 'N'),
      KeyCap('Key: M', 'M'),
      KeyCap('Key: ,', ','),
      KeyCap('Key: .', '.'),
      KeyCap('Key: /', '/'),
      KeyCap('Key: Right Shift', 'Shift', width: 2.75),
    ],
    nav: [KeyCap.gap(1), KeyCap('Key: Up Arrow', '↑'), KeyCap.gap(1)],
    numpad: [
      KeyCap('Key: Number Pad 1', '1'),
      KeyCap('Key: Number Pad 2', '2'),
      KeyCap('Key: Number Pad 3', '3'),
    ],
  ),
  // Bottom row
  KeyRow(
    main: [
      KeyCap('Key: Left Control', 'Ctrl', width: 1.25),
      KeyCap('Key: Left Fn', 'Fn', width: 1.25),
      KeyCap('Key: Left Windows', 'Win', width: 1.25),
      KeyCap('Key: Left Alt', 'Alt', width: 1.25),
      KeyCap('Key: Space', '', width: 7.5),
      KeyCap('Key: Right Alt', 'Alt', width: 1.25),
      KeyCap('Key: Right Control', 'Ctrl', width: 1.25),
    ],
    nav: [
      KeyCap('Key: Left Arrow', '←'),
      KeyCap('Key: Down Arrow', '↓'),
      KeyCap('Key: Right Arrow', '→'),
    ],
    numpad: [
      KeyCap('Key: Number Pad 0', '0', width: 2),
      KeyCap('Key: Number Pad .', '.'),
      KeyCap('Key: Number Pad Enter', 'Ent'),
    ],
  ),
];

/// Named key regions for one-tap "quick fill", mapped to their OpenRGB LED
/// names. Names that a given device doesn't expose are simply skipped.
final Map<String, List<String>> kKeyboardRegions = {
  'Function': [
    'Key: Escape',
    for (var i = 1; i <= 12; i++) 'Key: F$i',
    'Key: Print Screen',
  ],
  'Numbers': [
    'Key: `',
    for (final c in '1234567890'.split('')) 'Key: $c',
    'Key: -',
    'Key: =',
  ],
  'Letters': [
    for (final c in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) 'Key: $c',
  ],
  'WASD': ['Key: W', 'Key: A', 'Key: S', 'Key: D'],
  'Numpad': [
    'Key: Num Lock',
    for (final s in [
      '/',
      '*',
      '-',
      '7',
      '8',
      '9',
      '+',
      '4',
      '5',
      '6',
      '1',
      '2',
      '3',
      '0',
      '.',
      'Enter',
    ])
      'Key: Number Pad $s',
  ],
  'Arrows': [
    'Key: Up Arrow',
    'Key: Down Arrow',
    'Key: Left Arrow',
    'Key: Right Arrow',
  ],
  'Modifiers': [
    'Key: Left Control',
    'Key: Left Fn',
    'Key: Left Windows',
    'Key: Left Alt',
    'Key: Space',
    'Key: Right Alt',
    'Key: Right Control',
    'Key: Left Shift',
    'Key: Right Shift',
    'Key: Caps Lock',
    'Key: Tab',
    'Key: Enter',
    'Key: Backspace',
  ],
  'Neon': kNeonLeds,
};

/// The perimeter "Neon" accent LED names, in order.
const List<String> kNeonLeds = [
  'Neon group 1',
  'Neon group 2',
  'Neon group 3',
  'Neon group 4',
  'Neon group 5',
  'Neon group 6',
  'Neon group 7',
  'Neon group 8',
  'Neon group 9',
  'Neon group 10',
];
