import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

import 'keyboard_layout.dart';

/// A stylized, paintable keyboard. Each key is colored from [keyColors] (by the
/// LED index of its name in [leds]). Click a key — or press and **drag** across
/// keys — to paint with the active color ([onPaint]). Hold **Shift** to erase
/// ([onErase]) or **Alt** to eyedrop a key's color ([onPick]); all take the LED
/// index. Off keys render dim; the 10 "Neon group" LEDs show as a perimeter.
class KeyboardPreview extends StatefulWidget {
  const KeyboardPreview({
    super.key,
    required this.leds,
    required this.keyColors,
    required this.enabled,
    required this.onPaint,
    required this.onErase,
    required this.onPick,
  });

  final List<String> leds;
  final List<Color> keyColors;
  final bool enabled;
  final ValueChanged<int> onPaint;
  final ValueChanged<int> onErase;
  final ValueChanged<int> onPick;

  @override
  State<KeyboardPreview> createState() => _KeyboardPreviewState();
}

class _KeyboardPreviewState extends State<KeyboardPreview> {
  static const double _totalUnits =
      kMainUnits + kGroupGap + kNavUnits + kGroupGap + kNumpadUnits;

  bool _painting = false;

  int _indexOf(String led) {
    final index = widget.leds.indexOf(led);
    return (index >= 0 && index < widget.keyColors.length) ? index : -1;
  }

  /// Routes a key interaction by held modifier: Shift = erase, Alt = eyedrop
  /// (pick, only on a deliberate press, not a drag), otherwise paint.
  void _apply(int index, {required bool isDrag}) {
    if (!widget.enabled || index < 0) return;
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed) {
      widget.onErase(index);
    } else if (keys.isAltPressed) {
      if (!isDrag) widget.onPick(index);
    } else {
      widget.onPaint(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Listener(
      onPointerDown: (_) => setState(() => _painting = true),
      onPointerUp: (_) => setState(() => _painting = false),
      onPointerCancel: (_) => setState(() => _painting = false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final unit = (constraints.maxWidth / _totalUnits).clamp(16.0, 34.0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Click or drag to paint  ·  Shift = erase  ·  Alt = pick color',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              _neonStrip(),
              const SizedBox(height: 12),
              for (final row in kKeyboardLayout)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: kMainUnits * unit,
                        child: _group(row.main, unit),
                      ),
                      SizedBox(width: kGroupGap * unit),
                      SizedBox(
                        width: kNavUnits * unit,
                        child: _group(row.nav, unit),
                      ),
                      SizedBox(width: kGroupGap * unit),
                      SizedBox(
                        width: kNumpadUnits * unit,
                        child: _group(row.numpad, unit),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _group(List<KeyCap> caps, double unit) {
    return Row(
      children: [
        for (final cap in caps)
          cap.isGap ? SizedBox(width: cap.width * unit) : _keyTile(cap, unit),
      ],
    );
  }

  Widget _keyTile(KeyCap cap, double unit) {
    final scheme = Theme.of(context).colorScheme;
    final index = _indexOf(cap.led);
    final mapped = index >= 0;
    final color = mapped ? widget.keyColors[index] : null;
    final off = _isOff(color);

    return SizedBox(
      width: cap.width * unit,
      height: unit,
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: MouseRegion(
          cursor: (widget.enabled && mapped)
              ? SystemMouseCursors.click
              : MouseCursor.defer,
          onEnter: (_) {
            if (_painting) _apply(index, isDrag: true);
          },
          child: Listener(
            onPointerDown: (_) => _apply(index, isDrag: false),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: off ? scheme.surfaceContainerHighest : color!,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: scheme.onSurface.withValues(alpha: 0.12),
                ),
              ),
              child: Text(
                cap.label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: 8,
                  color: off
                      ? scheme.onSurface.withValues(alpha: 0.55)
                      : _contrast(color!),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _neonStrip() {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final name in kNeonLeds)
          Expanded(
            child: Builder(
              builder: (context) {
                final index = _indexOf(name);
                final color = index >= 0 ? widget.keyColors[index] : null;
                return MouseRegion(
                  onEnter: (_) {
                    if (_painting) _apply(index, isDrag: true);
                  },
                  child: Listener(
                    onPointerDown: (_) => _apply(index, isDrag: false),
                    child: Container(
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: _isOff(color)
                            ? scheme.surfaceContainerHighest
                            : color!,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

bool _isOff(Color? color) =>
    color == null || (color.r == 0 && color.g == 0 && color.b == 0);

Color _contrast(Color color) {
  final luminance = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b;
  return luminance > 0.6 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
}
