import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/lighting_bloc.dart';
import '../bloc/lighting_event.dart';
import '../providers/lighting_provider.dart';

class LightingPage extends ConsumerWidget {
  const LightingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lightingBlocProvider);
    final bloc = ref.read(lightingBlocProvider.bloc);

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    final scheme = Theme.of(context).colorScheme;

    return AppPageBody(
      title: 'Lighting',
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        AppControlCard(
          icon: YaruIcons.keyboard,
          title: 'Keyboard Backlight',
          children: [
            AppSwitchTile(
              value: state.whiteKeyboardBacklightEnabled ?? false,
              onChanged:
                  (state.whiteKeyboardBacklightSupported && !state.isApplying)
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Toggle white keyboard backlight',
                        message:
                            'Changing keyboard backlight uses privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      _setWhiteKeyboardBacklight(bloc, enabled);
                    }
                  : null,
              title: 'White keyboard backlight',
              subtitle: state.whiteKeyboardBacklightSupported
                  ? boolEnabledLabel(state.whiteKeyboardBacklightEnabled)
                  : 'Not supported on this device',
            ),
            const SizedBox(height: 8),
            YaruBanner.tile(
              color: scheme.surfaceContainerHighest,
              title: const Text('Per-key RGB (OpenRGB)'),
              subtitle: const Text(
                'OpenRGB integration coming in a future update.',
              ),
              icon: const Icon(Icons.keyboard_outlined),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppControlCard(
          icon: YaruIcons.color_select,
          title: 'Y-Logo Light',
          children: [
            AppSwitchTile(
              value: state.yLogoLightEnabled ?? false,
              onChanged: (state.yLogoLightSupported && !state.isApplying)
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Toggle Y-logo light',
                        message:
                            'Changing Y-logo lighting uses privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      _setYLogoLight(bloc, enabled);
                    }
                  : null,
              title: 'Y-logo light',
              subtitle: state.yLogoLightSupported
                  ? boolEnabledLabel(state.yLogoLightEnabled)
                  : 'Not supported on this device',
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppControlCard(
          icon: YaruIcons.thunderbolt,
          title: 'IO Port Light',
          children: [
            AppSwitchTile(
              value: state.ioPortLightEnabled ?? false,
              onChanged: (state.ioPortLightSupported && !state.isApplying)
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Toggle IO-port light',
                        message:
                            'Changing IO-port lighting uses privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      _setIoPortLight(bloc, enabled);
                    }
                  : null,
              title: 'IO-port light',
              subtitle: state.ioPortLightSupported
                  ? boolEnabledLabel(state.ioPortLightEnabled)
                  : 'Not supported on this device',
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppRefreshButton(
          isBusy: state.isLoading,
          onPressed: state.isApplying
              ? null
              : () => bloc.add(const LightingRefreshRequested()),
        ),
      ],
    );
  }

  void _setWhiteKeyboardBacklight(LightingBloc bloc, bool enabled) {
    bloc.add(WhiteKeyboardBacklightSetRequested(enabled));
  }

  void _setYLogoLight(LightingBloc bloc, bool enabled) {
    bloc.add(YLogoLightSetRequested(enabled));
  }

  void _setIoPortLight(LightingBloc bloc, bool enabled) {
    bloc.add(IoPortLightSetRequested(enabled));
  }
}
