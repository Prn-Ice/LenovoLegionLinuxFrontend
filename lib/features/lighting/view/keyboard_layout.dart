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

/// Approximate physical layout of the Legion keyboard, row by row. Names must
/// match the OpenRGB LED names; unmatched keys simply render non-paintable.
const List<List<KeyCap>> kKeyboardLayout = [
  // Function row
  [
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
    KeyCap.gap(0.4),
    KeyCap('Key: Print Screen', 'Prt'),
    KeyCap('Key: Insert', 'Ins'),
    KeyCap('Key: Delete', 'Del'),
  ],
  // Number row
  [
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
    KeyCap.gap(0.4),
    KeyCap('Key: Home', 'Hom'),
    KeyCap('Key: Page Up', 'PgU'),
    KeyCap.gap(0.4),
    KeyCap('Key: Num Lock', 'Num'),
    KeyCap('Key: Number Pad /', '/'),
    KeyCap('Key: Number Pad *', '*'),
    KeyCap('Key: Number Pad -', '-'),
  ],
  // Tab row
  [
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
    KeyCap.gap(0.4),
    KeyCap('Key: Delete', 'Del'),
    KeyCap('Key: End', 'End'),
    KeyCap('Key: Page Down', 'PgD'),
    KeyCap.gap(0.4),
    KeyCap('Key: Number Pad 7', '7'),
    KeyCap('Key: Number Pad 8', '8'),
    KeyCap('Key: Number Pad 9', '9'),
  ],
  // Caps row
  [
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
    KeyCap.gap(3.6),
    KeyCap('Key: Number Pad 4', '4'),
    KeyCap('Key: Number Pad 5', '5'),
    KeyCap('Key: Number Pad 6', '6'),
  ],
  // Shift row
  [
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
    KeyCap.gap(1.4),
    KeyCap('Key: Up Arrow', '↑'),
    KeyCap.gap(1.4),
    KeyCap('Key: Number Pad 1', '1'),
    KeyCap('Key: Number Pad 2', '2'),
    KeyCap('Key: Number Pad 3', '3'),
  ],
  // Bottom row
  [
    KeyCap('Key: Left Control', 'Ctrl', width: 1.25),
    KeyCap('Key: Left Fn', 'Fn', width: 1.25),
    KeyCap('Key: Left Windows', 'Win', width: 1.25),
    KeyCap('Key: Left Alt', 'Alt', width: 1.25),
    KeyCap('Key: Space', '', width: 5.5),
    KeyCap('Key: Right Alt', 'Alt', width: 1.25),
    KeyCap('Key: Right Control', 'Ctrl', width: 1.25),
    KeyCap.gap(0.4),
    KeyCap('Key: Left Arrow', '←'),
    KeyCap('Key: Down Arrow', '↓'),
    KeyCap('Key: Right Arrow', '→'),
    KeyCap.gap(0.4),
    KeyCap('Key: Number Pad 0', '0', width: 2),
    KeyCap('Key: Number Pad .', '.'),
    KeyCap('Key: Number Pad Enter', 'Ent'),
  ],
];

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
