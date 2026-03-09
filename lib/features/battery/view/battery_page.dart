import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../bloc/battery_event.dart';
import '../bloc/battery_state.dart';
import '../providers/battery_provider.dart';

class BatteryPage extends ConsumerWidget {
  const BatteryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(batteryBlocProvider);
    final bloc = ref.read(batteryBlocProvider.bloc);

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    final textTheme = Theme.of(context).textTheme;

    final batteryIcon = _batteryIcon(state);

    final chargingLabel = state.batteryCharging == true
        ? 'Charging'
        : state.batteryCharging == false
        ? 'Discharging'
        : 'AC status unknown';

    final double? health =
        (state.currentCapacityWh != null && state.designCapacityWh != null)
        ? state.currentCapacityWh! / state.designCapacityWh! * 100
        : null;

    final String powerDrawLabel =
        (state.batteryCharging == false && state.batteryPowerDrawW != null)
        ? '${state.batteryPowerDrawW!.abs().toStringAsFixed(1)} W'
        : '—';

    return AppPageBody(
      title: 'Battery',
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        // 1. Status header
        Row(
          children: [
            Icon(batteryIcon, size: 48),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.batteryPercent != null
                      ? '${state.batteryPercent}%'
                      : '—',
                  style: textTheme.headlineLarge,
                ),
                Text(chargingLabel),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 2. Health card
        AppControlCard(
          icon: YaruIcons.battery,
          title: 'Battery Health',
          children: [
            _infoTile(
              context,
              label: 'Current capacity',
              value:
                  '${state.currentCapacityWh?.toStringAsFixed(1) ?? '—'} Wh',
            ),
            _infoTile(
              context,
              label: 'Full charge capacity',
              value:
                  '${state.fullCapacityWh?.toStringAsFixed(1) ?? '—'} Wh',
            ),
            _infoTile(
              context,
              label: 'Design capacity',
              value:
                  '${state.designCapacityWh?.toStringAsFixed(1) ?? '—'} Wh',
            ),
            _infoTile(
              context,
              label: 'Battery health',
              value: health != null
                  ? '${health.toStringAsFixed(1)}%'
                  : '—',
            ),
            _infoTile(
              context,
              label: 'Charge cycles',
              value: '${state.cycleCounts ?? '—'}',
            ),
            _infoTile(
              context,
              label: 'Temperature',
              value:
                  '${state.batteryTempC?.toStringAsFixed(1) ?? '—'} °C',
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 3. Live stats card
        AppControlCard(
          icon: YaruIcons.thunderbolt,
          title: 'Live Statistics',
          children: [
            _infoTile(context, label: 'Power draw', value: powerDrawLabel),
          ],
        ),
        const SizedBox(height: 16),

        // 4. Controls card
        AppControlCard(
          icon: YaruIcons.settings,
          title: 'Controls',
          children: [
            AppSwitchTile(
              value: state.batteryConservationEnabled ?? false,
              onChanged:
                  (state.batteryConservationSupported && !state.isApplying)
                  ? (enabled) =>
                        bloc.add(BatteryConservationSetRequested(enabled))
                  : null,
              title: 'Battery Conservation',
              subtitle: state.batteryConservationSupported
                  ? boolEnabledLabel(state.batteryConservationEnabled)
                  : 'Not supported on this device',
            ),
            AppSwitchTile(
              value: state.rapidChargingEnabled ?? false,
              onChanged:
                  (state.rapidChargingSupported && !state.isApplying)
                  ? (enabled) =>
                        bloc.add(RapidChargingSetRequested(enabled))
                  : null,
              title: 'Rapid Charging',
              subtitle: state.rapidChargingSupported
                  ? boolEnabledLabel(state.rapidChargingEnabled)
                  : 'Not supported on this device',
            ),
          ],
        ),
        const SizedBox(height: 16),

        AppRefreshButton(
          isBusy: state.isLoading,
          onPressed: state.isApplying
              ? null
              : () => bloc.add(const BatteryRefreshRequested()),
        ),
      ],
    );
  }

  Widget _infoTile(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(value, style: textTheme.bodyLarge),
    );
  }

  IconData _batteryIcon(BatteryState state) {
    final percent = state.batteryPercent;
    if (percent == null) return YaruIcons.battery_missing;
    if (percent <= 10) return YaruIcons.battery_warning;
    if (percent <= 30) return YaruIcons.battery_2;
    if (percent <= 60) return YaruIcons.battery_6;
    return YaruIcons.battery_full;
  }
}
