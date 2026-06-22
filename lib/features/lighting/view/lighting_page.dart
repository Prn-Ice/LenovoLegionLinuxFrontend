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

class LightingPage extends ConsumerWidget {
  const LightingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rgb = ref.watch(rgbLightingBlocProvider);
    final rgbBloc = ref.read(rgbLightingBlocProvider.bloc);
    final lighting = ref.watch(lightingBlocProvider);
    final lightingBloc = ref.read(lightingBlocProvider.bloc);

    final device = rgb.device;

    return AppPageBody(
      errorMessage: rgb.errorMessage ?? lighting.errorMessage,
      noticeMessage: lighting.noticeMessage,
      children: [
        if (rgb.available && device != null) ...[
          _DeviceCard(device: device, activeMode: rgb.activeMode),
          const SizedBox(height: 16),
          _Section(
            title: 'Effect',
            child: _EffectPicker(
              modes: device.modes,
              activeMode: rgb.activeMode,
              enabled: !rgb.isApplying,
              onSelected: (mode) => rgbBloc.add(RgbModeSelected(mode)),
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Color',
            child: _ColorRow(
              selected: rgb.selectedColor,
              enabled: !rgb.isApplying,
              onSelected: (color) => rgbBloc.add(RgbColorSelected(color)),
              onFill: () => rgbBloc.add(RgbAllKeysFilled(rgb.selectedColor)),
            ),
          ),
          const SizedBox(height: 16),
          _BrightnessCard(
            brightness: rgb.brightness,
            enabled: !rgb.isApplying,
            onChanged: (value) => rgbBloc.add(RgbBrightnessChanged(value)),
          ),
        ] else
          const _UnavailableCard(),
        const SizedBox(height: 16),
        _BacklightSection(state: lighting, bloc: lightingBloc),
      ],
    );
  }
}

/// The OpenRGB keyboard identity card (magenta), with name + active effect.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.activeMode});

  final OpenRgbDevice device;
  final String? activeMode;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final facts = <String>[
      if (device.ledCount > 0) '${device.ledCount} keys',
      ?activeMode,
      'via OpenRGB',
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

class _ColorRow extends StatelessWidget {
  const _ColorRow({
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
    return Row(
      children: [
        Expanded(
          child: Wrap(
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
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: enabled ? onFill : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            side: BorderSide(color: _accent.withValues(alpha: 0.5)),
          ),
          child: const Text('Fill'),
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
        width: 30,
        height: 30,
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
/// complementary to the per-key RGB above.
class _BacklightSection extends StatelessWidget {
  const _BacklightSection({required this.state, required this.bloc});

  final LightingState state;
  final LightingBloc bloc;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Backlight',
      child: Column(
        children: [
          _toggle(
            context,
            icon: YaruIcons.keyboard,
            title: 'Keyboard backlight',
            supported: state.whiteKeyboardBacklightSupported,
            enabled: state.whiteKeyboardBacklightEnabled,
            confirmTitle: 'Toggle keyboard backlight',
            onApply: (v) => bloc.add(WhiteKeyboardBacklightSetRequested(v)),
          ),
          const SizedBox(height: 12),
          _toggle(
            context,
            icon: YaruIcons.color_select,
            title: 'Y-logo light',
            supported: state.yLogoLightSupported,
            enabled: state.yLogoLightEnabled,
            confirmTitle: 'Toggle Y-logo light',
            onApply: (v) => bloc.add(YLogoLightSetRequested(v)),
          ),
          const SizedBox(height: 12),
          _toggle(
            context,
            icon: YaruIcons.thunderbolt,
            title: 'IO-port light',
            supported: state.ioPortLightSupported,
            enabled: state.ioPortLightEnabled,
            confirmTitle: 'Toggle IO-port light',
            onApply: (v) => bloc.add(IoPortLightSetRequested(v)),
          ),
        ],
      ),
    );
  }

  Widget _toggle(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool supported,
    required bool? enabled,
    required String confirmTitle,
    required void Function(bool) onApply,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final on = enabled ?? false;
    final canToggle = supported && !state.isApplying;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
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
                Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(
                    color: supported ? null : scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  supported
                      ? (on ? 'On' : 'Off')
                      : 'Not supported on this device',
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
      ),
    );
  }
}

/// A titled section: a small caps label above [child].
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.5),
              letterSpacing: 1.1,
            ),
          ),
        ),
        child,
      ],
    );
  }
}
