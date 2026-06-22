import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../../../core/widgets/surface_card.dart';
import '../bloc/lighting_bloc.dart';
import '../bloc/lighting_event.dart';
import '../bloc/lighting_state.dart';
import '../bloc/rgb_lighting_event.dart';
import '../models/openrgb_device.dart';
import '../providers/lighting_provider.dart';
import '../repository/rgb_lighting_repository.dart';
import '../services/spectrum_effects.dart';
import 'keyboard_layout.dart';
import 'keyboard_preview.dart';

/// The lighting identity accent (magenta), local to this page — it does not
/// override the global power-mode accent.
const Color _accent = Color(0xFFD6409F);

const List<Color> _presetColors = [
  Color(0xFFFFFFFF),
  Color(0xFFFF3B30),
  Color(0xFFFF7A00),
  Color(0xFFFFD400),
  Color(0xFF2ECC40),
  Color(0xFF00C2D1),
  Color(0xFF3D7BFF),
  _accent,
];

/// Curated effect order; filtered down to what the device actually supports so
/// the noisy raw OpenRGB modes (Screw Rainbow, Audio Bounce, …) stay hidden.
const List<String> _curatedEffects = [
  'Static',
  'Direct',
  'Rainbow Wave',
  'Color Pulse',
  'Color Wave',
  'Smooth',
  'Ripple',
  'Rain',
  'Color Change',
  'Type Lighting',
];

List<String> _effectsFor(List<String> modes, String? active) {
  final available = modes.toSet();
  final result = [
    for (final mode in _curatedEffects)
      if (available.contains(mode)) mode,
  ];
  if (active != null &&
      available.contains(active) &&
      !result.contains(active)) {
    result.insert(0, active);
  }
  return result;
}

class LightingPage extends ConsumerWidget {
  const LightingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rgb = ref.watch(rgbLightingBlocProvider);
    final rgbBloc = ref.read(rgbLightingBlocProvider.bloc);
    final lighting = ref.watch(lightingBlocProvider);
    final lightingBloc = ref.read(lightingBlocProvider.bloc);
    final engine = ref.watch(spectrumEffectEngineProvider);

    final device = rgb.device;

    // Keep the animation engine in sync with the painting + effect assignments.
    ref.listen(rgbLightingBlocProvider, (_, next) {
      final dev = next.device;
      if (next.available && dev != null) {
        engine.configure(
          base: next.keyColors,
          leds: dev.leds,
          effects: next.effects,
        );
      }
    });

    return AppPageBody(
      errorMessage: rgb.errorMessage ?? lighting.errorMessage,
      noticeMessage: lighting.noticeMessage,
      children: [
        if (rgb.available && device != null) ...[
          _DeviceCard(
            device: device,
            activeMode: rgb.activeMode,
            nativeAvailable: rgb.nativeAvailable,
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<List<Color>?>(
            valueListenable: engine.frame,
            builder: (context, liveFrame, _) => _KeyboardCard(
              leds: device.leds,
              keyColors: liveFrame ?? rgb.keyColors,
              enabled: !rgb.isApplying,
              onPaint: (index) => rgbBloc.add(RgbKeyPainted(index)),
              onErase: (index) => rgbBloc.add(RgbKeyErased(index)),
              onPick: (index) => rgbBloc.add(RgbKeyPicked(index)),
            ),
          ),
          const SizedBox(height: 16),
          _ColorCard(
            selected: rgb.selectedColor,
            enabled: !rgb.isApplying,
            onSelected: (color) => rgbBloc.add(RgbColorSelected(color)),
            onFill: () => rgbBloc.add(RgbAllKeysFilled(rgb.selectedColor)),
          ),
          const SizedBox(height: 16),
          _QuickFillCard(
            leds: device.leds,
            enabled: !rgb.isApplying,
            onFill: (indices) => rgbBloc.add(RgbRegionFilled(indices)),
          ),
          const SizedBox(height: 16),
          _ControlCard(
            title: 'Effect',
            child: _EffectPicker(
              modes: _effectsFor(device.modes, rgb.activeMode),
              activeMode: rgb.activeMode,
              enabled: !rgb.isApplying,
              onSelected: (mode) => rgbBloc.add(RgbModeSelected(mode)),
            ),
          ),
          const SizedBox(height: 16),
          _AnimatedEffectsCard(
            leds: device.leds,
            activeEffects: rgb.effects,
            enabled: !rgb.isApplying,
            onAssign: (scope, indices, effect) =>
                rgbBloc.add(RgbEffectAssigned(scope, indices, effect)),
            onClear: () => rgbBloc.add(const RgbEffectsCleared()),
          ),
          const SizedBox(height: 16),
          _BrightnessCard(
            brightness: rgb.brightness,
            enabled: !rgb.isApplying,
            onChanged: (value) => rgbBloc.add(RgbBrightnessChanged(value)),
          ),
          const SizedBox(height: 16),
          _ProfilesCard(
            profileNames: rgb.profileNames,
            enabled: !rgb.isApplying,
            onSave: (name) => rgbBloc.add(RgbProfileSaved(name)),
            onLoad: (name) => rgbBloc.add(RgbProfileLoaded(name)),
            onDelete: (name) => rgbBloc.add(RgbProfileDeleted(name)),
          ),
        ] else
          const _UnavailableCard(),
        const SizedBox(height: 16),
        _BacklightSection(state: lighting, bloc: lightingBloc),
      ],
    );
  }
}

/// A SurfaceCard with a small caps title, for grouping a control.
class _ControlCard extends StatelessWidget {
  const _ControlCard({required this.title, required this.child, this.color});

  final String title;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.5),
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// The OpenRGB keyboard identity card (magenta), with name + active effect.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.activeMode,
    required this.nativeAvailable,
  });

  final OpenRgbDevice device;
  final String? activeMode;
  final bool nativeAvailable;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final facts = <String>[
      if (device.ledCount > 0) '${device.ledCount} keys',
      ?activeMode,
      if (nativeAvailable) 'real-time' else 'via OpenRGB',
    ].join('  ·  ');

    return SurfaceCard(
      color: Color.alphaBlend(_accent.withValues(alpha: 0.10), scheme.surface),
      border: Border.all(color: _accent.withValues(alpha: 0.45)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(YaruIcons.keyboard, color: _accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(device.name, style: textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  facts,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The keyboard preview on a darker surface so the keys pop, like the design.
class _KeyboardCard extends StatelessWidget {
  const _KeyboardCard({
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ControlCard(
      title: 'Per-key',
      color: Color.alphaBlend(
        Colors.black.withValues(alpha: 0.4),
        scheme.surface,
      ),
      child: KeyboardPreview(
        leds: leds,
        keyColors: keyColors,
        enabled: enabled,
        onPaint: onPaint,
        onErase: onErase,
        onPick: onPick,
      ),
    );
  }
}

/// One-tap fills for named key regions (Function row, Numpad, …). Resolves each
/// region's LED names against [leds] and emits the matched indices.
class _QuickFillCard extends StatelessWidget {
  const _QuickFillCard({
    required this.leds,
    required this.enabled,
    required this.onFill,
  });

  final List<String> leds;
  final bool enabled;
  final ValueChanged<List<int>> onFill;

  @override
  Widget build(BuildContext context) {
    return _ControlCard(
      title: 'Quick fill',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in kKeyboardRegions.entries)
            ActionChip(
              label: Text(entry.key),
              onPressed: enabled
                  ? () {
                      final indices = <int>[];
                      for (final name in entry.value) {
                        final index = leds.indexOf(name);
                        if (index >= 0) indices.add(index);
                      }
                      if (indices.isNotEmpty) onFill(indices);
                    }
                  : null,
            ),
        ],
      ),
    );
  }
}

/// Software animated effects, assignable per region (Pulse/Wave/Rainbow). They
/// run over the native path — the hardware can only animate the whole board.
class _AnimatedEffectsCard extends StatefulWidget {
  const _AnimatedEffectsCard({
    required this.leds,
    required this.activeEffects,
    required this.enabled,
    required this.onAssign,
    required this.onClear,
  });

  final List<String> leds;
  final List<SpectrumRegionEffect> activeEffects;
  final bool enabled;
  final void Function(String scope, List<int> indices, SpectrumEffect effect)
  onAssign;
  final VoidCallback onClear;

  @override
  State<_AnimatedEffectsCard> createState() => _AnimatedEffectsCardState();
}

class _AnimatedEffectsCardState extends State<_AnimatedEffectsCard> {
  String _scope = 'All';

  List<int> _indicesFor(String scope) {
    if (scope == 'All') {
      return [for (var i = 0; i < widget.leds.length; i++) i];
    }
    final indices = <int>[];
    for (final name in kKeyboardRegions[scope] ?? const <String>[]) {
      final index = widget.leds.indexOf(name);
      if (index >= 0) indices.add(index);
    }
    return indices;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Widget caption(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: textTheme.bodySmall?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );

    return _ControlCard(
      title: 'Animated effects',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          caption('Region'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final scope in ['All', ...kKeyboardRegions.keys])
                ChoiceChip(
                  label: Text(scope),
                  selected: _scope == scope,
                  selectedColor: _accent.withValues(alpha: 0.22),
                  side: _scope == scope
                      ? const BorderSide(color: _accent)
                      : null,
                  onSelected: widget.enabled
                      ? (_) => setState(() => _scope = scope)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 14),
          caption('Effect'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final effect in SpectrumEffect.values)
                ActionChip(
                  label: Text(_effectLabel(effect)),
                  onPressed: widget.enabled
                      ? () {
                          final indices = _indicesFor(_scope);
                          if (indices.isNotEmpty) {
                            widget.onAssign(_scope, indices, effect);
                          }
                        }
                      : null,
                ),
            ],
          ),
          if (widget.activeEffects.isNotEmpty) ...[
            const Divider(height: 28),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final effect in widget.activeEffects)
                  Chip(
                    label: Text(
                      '${effect.label} · ${_effectLabel(effect.effect)}',
                    ),
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                TextButton.icon(
                  onPressed: widget.enabled ? widget.onClear : null,
                  icon: const Icon(YaruIcons.window_close, size: 16),
                  label: const Text('Stop all'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _effectLabel(SpectrumEffect effect) => switch (effect) {
  SpectrumEffect.pulse => 'Pulse',
  SpectrumEffect.wave => 'Wave',
  SpectrumEffect.rainbow => 'Rainbow',
};

/// Named profiles: save the current setup under a name, then tap to re-apply or
/// the × to delete. The whole config (colors, brightness, effects) is stored.
class _ProfilesCard extends StatefulWidget {
  const _ProfilesCard({
    required this.profileNames,
    required this.enabled,
    required this.onSave,
    required this.onLoad,
    required this.onDelete,
  });

  final List<String> profileNames;
  final bool enabled;
  final ValueChanged<String> onSave;
  final ValueChanged<String> onLoad;
  final ValueChanged<String> onDelete;

  @override
  State<_ProfilesCard> createState() => _ProfilesCardState();
}

class _ProfilesCardState extends State<_ProfilesCard> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    widget.onSave(name);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return _ControlCard(
      title: 'Profiles',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: widget.enabled,
                  decoration: const InputDecoration(
                    hintText: 'Profile name',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: widget.enabled ? _save : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: BorderSide(color: _accent.withValues(alpha: 0.5)),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
          if (widget.profileNames.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in widget.profileNames)
                  InputChip(
                    label: Text(name),
                    onPressed: widget.enabled
                        ? () => widget.onLoad(name)
                        : null,
                    onDeleted: widget.enabled
                        ? () => widget.onDelete(name)
                        : null,
                    deleteIcon: const Icon(YaruIcons.window_close, size: 16),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ColorCard extends StatelessWidget {
  const _ColorCard({
    required this.selected,
    required this.enabled,
    required this.onSelected,
    required this.onFill,
  });

  final Color selected;
  final bool enabled;
  final ValueChanged<Color> onSelected;
  final VoidCallback onFill;

  @override
  Widget build(BuildContext context) {
    return _ControlCard(
      title: 'Color',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ColorPicker(
            selected: selected,
            onChanged: enabled ? onSelected : (_) {},
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _HexField(
                  color: selected,
                  enabled: enabled,
                  onChanged: onSelected,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final color in _presetColors)
                      _Swatch(
                        color: color,
                        selected: color == selected,
                        onTap: enabled ? () => onSelected(color) : null,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: enabled ? onFill : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: BorderSide(color: _accent.withValues(alpha: 0.5)),
                  ),
                  child: const Text('Fill keyboard'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A precise color picker: a saturation/value square over the current hue, plus
/// a hue slider. Tap or drag either — reaches every color (white, pastels, dim
/// shades, warm whites), unlike a hue-only wheel. Keeps a remembered hue so
/// greys/whites don't lose it.
class _ColorPicker extends StatefulWidget {
  const _ColorPicker({required this.selected, required this.onChanged});

  final Color selected;
  final ValueChanged<Color> onChanged;

  static const double width = 150;
  static const double svHeight = 110;
  static const double hueHeight = 16;

  @override
  State<_ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  late double _hue = HSVColor.fromColor(widget.selected).hue;

  @override
  void didUpdateWidget(_ColorPicker old) {
    super.didUpdateWidget(old);
    final hsv = HSVColor.fromColor(widget.selected);
    if (hsv.saturation > 0.02 && hsv.value > 0.02) _hue = hsv.hue;
  }

  void _pickSv(Offset p) {
    final s = (p.dx / _ColorPicker.width).clamp(0.0, 1.0);
    final v = (1 - p.dy / _ColorPicker.svHeight).clamp(0.0, 1.0);
    widget.onChanged(HSVColor.fromAHSV(1, _hue, s, v).toColor());
  }

  void _pickHue(Offset p) {
    setState(() => _hue = (p.dx / _ColorPicker.width * 360).clamp(0.0, 359.99));
    final hsv = HSVColor.fromColor(widget.selected);
    widget.onChanged(
      HSVColor.fromAHSV(1, _hue, hsv.saturation, hsv.value).toColor(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(widget.selected);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onPanDown: (d) => _pickSv(d.localPosition),
          onPanUpdate: (d) => _pickSv(d.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CustomPaint(
              size: const Size(_ColorPicker.width, _ColorPicker.svHeight),
              painter: _SvPainter(_hue, hsv.saturation, hsv.value),
            ),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onPanDown: (d) => _pickHue(d.localPosition),
          onPanUpdate: (d) => _pickHue(d.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_ColorPicker.hueHeight / 2),
            child: CustomPaint(
              size: const Size(_ColorPicker.width, _ColorPicker.hueHeight),
              painter: _HuePainter(_hue),
            ),
          ),
        ),
      ],
    );
  }
}

class _SvPainter extends CustomPainter {
  _SvPainter(this.hue, this.saturation, this.value);

  final double hue;
  final double saturation;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [const Color(0xFFFFFFFF), hueColor],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
        ).createShader(rect),
    );
    final knob = Offset(saturation * size.width, (1 - value) * size.height);
    canvas.drawCircle(
      knob,
      6,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SvPainter old) =>
      old.hue != hue || old.saturation != saturation || old.value != value;
}

class _HuePainter extends CustomPainter {
  _HuePainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            for (var h = 0; h <= 360; h += 60)
              HSVColor.fromAHSV(1, (h % 360).toDouble(), 1, 1).toColor(),
          ],
        ).createShader(rect),
    );
    final x = hue / 360 * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, size.height / 2),
          width: 5,
          height: size.height,
        ),
        const Radius.circular(2.5),
      ),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}

/// An editable `RRGGBB` hex field for typing an exact color.
class _HexField extends StatefulWidget {
  const _HexField({
    required this.color,
    required this.enabled,
    required this.onChanged,
  });

  final Color color;
  final bool enabled;
  final ValueChanged<Color> onChanged;

  @override
  State<_HexField> createState() => _HexFieldState();
}

class _HexFieldState extends State<_HexField> {
  late final TextEditingController _controller = TextEditingController(
    text: colorToOpenRgbHex(widget.color),
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(_HexField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus) {
      final hex = colorToOpenRgbHex(widget.color);
      if (_controller.text.toUpperCase() != hex) _controller.text = hex;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    final cleaned = raw.replaceAll('#', '').trim();
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(cleaned)) {
      widget.onChanged(Color(0xFF000000 | int.parse(cleaned, radix: 16)));
    } else {
      _controller.text = colorToOpenRgbHex(widget.color);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: 132,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: widget.enabled,
        style: textTheme.titleMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        decoration: const InputDecoration(
          prefixText: '#',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.characters,
        onSubmitted: _submit,
        onTapOutside: (_) {
          if (_focus.hasFocus) {
            _submit(_controller.text);
            _focus.unfocus();
          }
        },
      ),
    );
  }
}

class _EffectPicker extends StatelessWidget {
  const _EffectPicker({
    required this.modes,
    required this.activeMode,
    required this.enabled,
    required this.onSelected,
  });

  final List<String> modes;
  final String? activeMode;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final mode in modes)
          ChoiceChip(
            label: Text(mode),
            selected: activeMode == mode,
            selectedColor: _accent.withValues(alpha: 0.22),
            side: activeMode == mode ? const BorderSide(color: _accent) : null,
            onSelected: enabled ? (_) => onSelected(mode) : null,
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? scheme.onSurface
                : scheme.onSurface.withValues(alpha: 0.2),
            width: selected ? 2.5 : 1,
          ),
        ),
      ),
    );
  }
}

class _BrightnessCard extends StatefulWidget {
  const _BrightnessCard({
    required this.brightness,
    required this.enabled,
    required this.onChanged,
  });

  final int brightness;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<_BrightnessCard> createState() => _BrightnessCardState();
}

class _BrightnessCardState extends State<_BrightnessCard> {
  late double _value = widget.brightness.toDouble();

  @override
  void didUpdateWidget(_BrightnessCard old) {
    super.didUpdateWidget(old);
    if (old.brightness != widget.brightness) {
      _value = widget.brightness.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Brightness', style: textTheme.titleSmall),
              Text('${_value.round()}%', style: textTheme.bodySmall),
            ],
          ),
          Slider(
            value: _value,
            max: 100,
            activeColor: _accent,
            onChanged: widget.enabled
                ? (value) => setState(() => _value = value)
                : null,
            onChangeEnd: (value) => widget.onChanged(value.round()),
          ),
        ],
      ),
    );
  }
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(YaruIcons.keyboard, color: _accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Per-key RGB unavailable', style: textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'Start OpenRGB (with its udev rules) to control the keyboard '
                  'RGB. The backlight toggles below still work.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The coarse sysfs backlight zones (white keyboard / Y-logo / IO-port),
/// complementary to the per-key RGB above. Hidden when none are supported.
class _BacklightSection extends StatelessWidget {
  const _BacklightSection({required this.state, required this.bloc});

  final LightingState state;
  final LightingBloc bloc;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      if (state.whiteKeyboardBacklightSupported)
        _toggle(
          context,
          icon: YaruIcons.keyboard,
          title: 'Keyboard backlight',
          enabled: state.whiteKeyboardBacklightEnabled,
          confirmTitle: 'Toggle keyboard backlight',
          onApply: (v) => bloc.add(WhiteKeyboardBacklightSetRequested(v)),
        ),
      if (state.yLogoLightSupported)
        _toggle(
          context,
          icon: YaruIcons.color_select,
          title: 'Y-logo light',
          enabled: state.yLogoLightEnabled,
          confirmTitle: 'Toggle Y-logo light',
          onApply: (v) => bloc.add(YLogoLightSetRequested(v)),
        ),
      if (state.ioPortLightSupported)
        _toggle(
          context,
          icon: YaruIcons.thunderbolt,
          title: 'IO-port light',
          enabled: state.ioPortLightEnabled,
          confirmTitle: 'Toggle IO-port light',
          onApply: (v) => bloc.add(IoPortLightSetRequested(v)),
        ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return _ControlCard(
      title: 'Backlight',
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            tiles[i],
          ],
        ],
      ),
    );
  }

  Widget _toggle(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool? enabled,
    required String confirmTitle,
    required void Function(bool) onApply,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final on = enabled ?? false;
    final canToggle = !state.isApplying;

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: _accent, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: textTheme.titleSmall),
              Text(
                on ? 'On' : 'Off',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        YaruSwitch(
          value: on,
          onChanged: canToggle
              ? (v) async {
                  final confirmed = await confirmPrivilegedAction(
                    context,
                    title: confirmTitle,
                    message:
                        'This uses privileged access and may prompt for '
                        'authentication.',
                    confirmLabel: 'Apply',
                  );
                  if (!context.mounted || !confirmed) return;
                  onApply(v);
                }
              : null,
        ),
      ],
    );
  }
}
