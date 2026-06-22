import 'package:equatable/equatable.dart';

/// A single RGB device as reported by `openrgb --list-devices`.
class OpenRgbDevice extends Equatable {
  const OpenRgbDevice({
    required this.index,
    required this.name,
    this.type = '',
    this.description = '',
    this.modes = const [],
    this.activeMode,
    this.zones = const [],
    this.leds = const [],
  });

  /// The `-d` device index passed to the CLI.
  final int index;
  final String name;
  final String type;
  final String description;

  /// Effect/mode names, e.g. `Static`, `Rainbow Wave`, `Direct`.
  final List<String> modes;

  /// The mode shown in `[brackets]` (currently applied), if any.
  final String? activeMode;

  /// Zone names, e.g. `Keyboard`, `Neon`.
  final List<String> zones;

  /// Per-LED names, in the order the CLI's `-c` color list addresses them.
  final List<String> leds;

  int get ledCount => leds.length;

  @override
  List<Object?> get props => [
    index,
    name,
    type,
    description,
    modes,
    activeMode,
    zones,
    leds,
  ];
}

/// Parses the textual output of `openrgb --list-devices` into devices. Server
/// chatter lines (e.g. "Connected to server") and blank lines are ignored.
List<OpenRgbDevice> parseOpenRgbDevices(String output) {
  final devices = <OpenRgbDevice>[];

  int? index;
  var name = '';
  var type = '';
  var description = '';
  var modes = const <String>[];
  String? activeMode;
  var zones = const <String>[];
  var leds = const <String>[];

  void flush() {
    final idx = index;
    if (idx != null) {
      devices.add(
        OpenRgbDevice(
          index: idx,
          name: name,
          type: type,
          description: description,
          modes: modes,
          activeMode: activeMode,
          zones: zones,
          leds: leds,
        ),
      );
    }
  }

  for (final raw in output.split('\n')) {
    final header = RegExp(r'^(\d+):\s*(.+)$').firstMatch(raw);
    if (header != null) {
      flush();
      index = int.parse(header.group(1)!);
      name = header.group(2)!.trim();
      type = '';
      description = '';
      modes = const [];
      activeMode = null;
      zones = const [];
      leds = const [];
      continue;
    }

    if (index == null) continue;
    final line = raw.trim();
    if (line.startsWith('Type:')) {
      type = line.substring('Type:'.length).trim();
    } else if (line.startsWith('Description:')) {
      description = line.substring('Description:'.length).trim();
    } else if (line.startsWith('Modes:')) {
      final parsed = _tokenize(line.substring('Modes:'.length).trim());
      modes = parsed.names;
      activeMode = parsed.active;
    } else if (line.startsWith('Zones:')) {
      zones = _tokenize(line.substring('Zones:'.length).trim()).names;
    } else if (line.startsWith('LEDs:')) {
      leds = _tokenize(line.substring('LEDs:'.length).trim()).names;
    }
  }
  flush();
  return devices;
}

/// Splits an OpenRGB token list into names, honoring `'quoted'` multi-word
/// names and the `[bracketed]` active marker. Returns the names in order plus
/// the bracketed name (if present).
({List<String> names, String? active}) _tokenize(String s) {
  final names = <String>[];
  String? active;
  var i = 0;

  while (i < s.length) {
    if (s[i] == ' ') {
      i++;
      continue;
    }

    var bracketed = false;
    if (s[i] == '[') {
      bracketed = true;
      i++;
    }

    final String name;
    if (i < s.length && s[i] == "'") {
      i++;
      final start = i;
      while (i < s.length && s[i] != "'") {
        i++;
      }
      name = s.substring(start, i);
      if (i < s.length) i++; // closing quote
    } else {
      final start = i;
      while (i < s.length && s[i] != ' ' && s[i] != ']') {
        i++;
      }
      name = s.substring(start, i);
    }

    if (bracketed) {
      while (i < s.length && s[i] != ']') {
        i++;
      }
      if (i < s.length) i++; // closing bracket
      active = name;
    }

    if (name.isNotEmpty) names.add(name);
  }

  return (names: names, active: active);
}
