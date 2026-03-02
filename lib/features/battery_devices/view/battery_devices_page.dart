import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/battery_devices_event.dart';
import '../providers/battery_devices_provider.dart';

class BatteryDevicesPage extends ConsumerWidget {
  const BatteryDevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(batteryDevicesBlocProvider);
    final bloc = ref.read(batteryDevicesBlocProvider.bloc);
    final textTheme = Theme.of(context).textTheme;

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Battery & Devices', style: textTheme.headlineMedium),
        const SizedBox(height: 16),
        if (state.errorMessage != null) ...[
          Text(
            state.errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
        ],
        if (state.noticeMessage != null) ...[
          Text(
            state.noticeMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 8),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Battery', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                const PrivilegedActionNotice(),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: state.batteryConservationEnabled ?? false,
                  onChanged:
                      _isWritable(
                        state.batteryConservationEnabled,
                        state.isApplying,
                      )
                      ? (enabled) async {
                          final confirmed = await confirmPrivilegedAction(
                            context,
                            title: 'Set battery conservation',
                            message:
                                'This action uses privileged access and may prompt for authentication.',
                            confirmLabel: 'Apply',
                          );
                          if (!context.mounted || !confirmed) {
                            return;
                          }
                          bloc.add(BatteryConservationSetRequested(enabled));
                        }
                      : null,
                  title: const Text('Battery conservation'),
                  subtitle: Text(_statusText(state.batteryConservationEnabled)),
                ),
                SwitchListTile.adaptive(
                  value: state.rapidChargingEnabled ?? false,
                  onChanged:
                      _isWritable(state.rapidChargingEnabled, state.isApplying)
                      ? (enabled) async {
                          final confirmed = await confirmPrivilegedAction(
                            context,
                            title: 'Set rapid charging',
                            message:
                                'This action uses privileged access and may prompt for authentication.',
                            confirmLabel: 'Apply',
                          );
                          if (!context.mounted || !confirmed) {
                            return;
                          }
                          bloc.add(RapidChargingSetRequested(enabled));
                        }
                      : null,
                  title: const Text('Rapid charging'),
                  subtitle: Text(_statusText(state.rapidChargingEnabled)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Always-on USB charging'),
                  subtitle: Text(
                    state.alwaysOnUsbChargingEnabled == null
                        ? 'Unavailable on this device'
                        : '${_statusText(state.alwaysOnUsbChargingEnabled)} (read-only: write path blocked in backend)',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Input Devices', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                const PrivilegedActionNotice(),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: state.touchpadEnabled ?? false,
                  onChanged:
                      _isWritable(state.touchpadEnabled, state.isApplying)
                      ? (enabled) async {
                          final confirmed = await confirmPrivilegedAction(
                            context,
                            title: 'Set touchpad state',
                            message:
                                'This action uses privileged access and may prompt for authentication.',
                            confirmLabel: 'Apply',
                          );
                          if (!context.mounted || !confirmed) {
                            return;
                          }
                          bloc.add(TouchpadSetRequested(enabled));
                        }
                      : null,
                  title: const Text('Touchpad'),
                  subtitle: Text(_statusText(state.touchpadEnabled)),
                ),
                SwitchListTile.adaptive(
                  value: state.winKeyEnabled ?? false,
                  onChanged: _isWritable(state.winKeyEnabled, state.isApplying)
                      ? (enabled) async {
                          final confirmed = await confirmPrivilegedAction(
                            context,
                            title: 'Set Win key lock',
                            message:
                                'This action uses privileged access and may prompt for authentication.',
                            confirmLabel: 'Apply',
                          );
                          if (!context.mounted || !confirmed) {
                            return;
                          }
                          bloc.add(WinKeySetRequested(enabled));
                        }
                      : null,
                  title: const Text('Win key'),
                  subtitle: Text(_statusText(state.winKeyEnabled)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Camera power'),
                  subtitle: Text(
                    state.cameraPowerEnabled == null
                        ? 'Unavailable on this device'
                        : '${_statusText(state.cameraPowerEnabled)} (read-only)',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: state.isLoading || state.isApplying
              ? null
              : () => bloc.add(const BatteryDevicesRefreshRequested()),
          icon: state.isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  bool _isWritable(bool? value, bool isApplying) {
    return value != null && !isApplying;
  }

  String _statusText(bool? value) {
    if (value == null) {
      return 'Unavailable on this device';
    }
    return value ? 'Enabled' : 'Disabled';
  }
}
