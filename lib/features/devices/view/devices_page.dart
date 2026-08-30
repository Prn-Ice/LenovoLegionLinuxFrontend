import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../bloc/devices_event.dart';
import '../providers/devices_provider.dart';

class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(devicesBlocProvider);
    final bloc = ref.read(devicesBlocProvider.bloc);

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    return AppPageBody(
      title: 'Devices',
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        // 1. Input card
        AppControlCard(
          icon: YaruIcons.keyboard,
          title: 'Input',
          children: [
            AppSwitchTile(
              value: state.touchpadEnabled ?? false,
              onChanged: (state.touchpadSupported && !state.isApplying)
                  ? (enabled) => bloc.add(TouchpadSetRequested(enabled))
                  : null,
              title: 'Touchpad',
              subtitle: state.touchpadSupported
                  ? boolEnabledLabel(state.touchpadEnabled)
                  : 'Not supported on this device',
            ),
            AppSwitchTile(
              value: state.winKeyEnabled ?? false,
              onChanged: (state.winKeySupported && !state.isApplying)
                  ? (enabled) => bloc.add(WinKeySetRequested(enabled))
                  : null,
              title: 'Win Key',
              subtitle: state.winKeySupported
                  ? boolEnabledLabel(state.winKeyEnabled)
                  : 'Not supported on this device',
            ),
            AppSwitchTile(
              value: state.fnLockEnabled ?? false,
              onChanged: (state.fnLockSupported && !state.isApplying)
                  ? (enabled) => bloc.add(FnLockSetRequested(enabled))
                  : null,
              title: 'Fn Lock',
              subtitle: state.fnLockSupported
                  ? boolEnabledLabel(state.fnLockEnabled)
                  : 'Not supported on this device',
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 2. Camera card
        AppControlCard(
          icon: YaruIcons.camera_web,
          title: 'Camera',
          children: [
            AppSwitchTile(
              value: state.cameraEnabled ?? false,
              onChanged: (state.cameraSupported && !state.isApplying)
                  ? (enabled) => bloc.add(CameraSetRequested(enabled))
                  : null,
              title: 'Camera',
              subtitle: state.cameraSupported
                  ? boolEnabledLabel(state.cameraEnabled)
                  : 'Not supported on this device',
            ),
          ],
        ),
        const SizedBox(height: 16),

        AppRefreshButton(
          isBusy: state.isLoading,
          onPressed: state.isApplying
              ? null
              : () => bloc.add(const DevicesRefreshRequested()),
        ),
      ],
    );
  }
}
