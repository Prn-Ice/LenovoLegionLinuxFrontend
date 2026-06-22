import 'package:flutter/material.dart';

import 'keyboard_layout.dart';

/// A stylized, paintable keyboard. Each key is colored from [keyColors] (by the
/// LED index of its name in [leds]); tapping a key reports its LED index via
/// [onPaint]. Rows are laid out in three fixed-width column groups (main / nav /
/// numpad) so the clusters line up. Scales to the available width.
class KeyboardPreview extends StatelessWidget {
  const KeyboardPreview({
    super.key,
    required this.leds,
    required this.keyColors,
    required this.enabled,
    required this.onPaint,
  });

  final List<String> leds;
  final List<Color> keyColors;
  final bool enabled;
  final ValueChanged<int> onPaint;

  static const double _totalUnits =
      kMainUnits + kGroupGap + kNavUnits + kGroupGap + kNumpadUnits;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final unit = (constraints.maxWidth / _totalUnits).clamp(16.0, 34.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _NeonStrip(
              leds: leds,
              colors: keyColors,
              enabled: enabled,
              onPaint: onPaint,
            ),
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
    );
  }

  Widget _group(List<KeyCap> caps, double unit) {
    return Row(
      children: [
        for (final cap in caps)
          cap.isGap
              ? SizedBox(width: cap.width * unit)
              : _Key(
                  cap: cap,
                  unit: unit,
                  index: _indexOf(cap.led),
                  colors: keyColors,
                  enabled: enabled,
                  onPaint: onPaint,
                ),
      ],
    );
  }

  int _indexOf(String led) {
    final index = leds.indexOf(led);
    return (index >= 0 && index < keyColors.length) ? index : -1;
  }
}

bool _isOff(Color? color) =>
    color == null || (color.r == 0 && color.g == 0 && color.b == 0);

Color _contrast(Color color) {
  final luminance = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b;
  return luminance > 0.6 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
}

class _Key extends StatelessWidget {
  const _Key({
    required this.cap,
    required this.unit,
    required this.index,
    required this.colors,
    required this.enabled,
    required this.onPaint,
  });

  final KeyCap cap;
  final double unit;
  final int index;
  final List<Color> colors;
  final bool enabled;
  final ValueChanged<int> onPaint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mapped = index >= 0;
    final color = mapped ? colors[index] : null;
    final off = _isOff(color);
    final fill = off ? scheme.surfaceContainerHighest : color!;

    return SizedBox(
      width: cap.width * unit,
      height: unit,
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: GestureDetector(
          onTap: (enabled && mapped) ? () => onPaint(index) : null,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
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
    );
  }
}

class _NeonStrip extends StatelessWidget {
  const _NeonStrip({
    required this.leds,
    required this.colors,
    required this.enabled,
    required this.onPaint,
  });

  final List<String> leds;
  final List<Color> colors;
  final bool enabled;
  final ValueChanged<int> onPaint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final name in kNeonLeds)
          Expanded(
            child: Builder(
              builder: (context) {
                final index = leds.indexOf(name);
                final mapped = index >= 0 && index < colors.length;
                final color = mapped ? colors[index] : null;
                return GestureDetector(
                  onTap: (enabled && mapped) ? () => onPaint(index) : null,
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
                );
              },
            ),
          ),
      ],
    );
  }
}
