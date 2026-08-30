import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/metric_text.dart';
import '../../../core/widgets/surface_card.dart';
import '../../analytics/bloc/analytics_event.dart';
import '../../analytics/models/sensor_record.dart';
import '../../analytics/models/sensor_records_csv.dart';
import '../../analytics/providers/analytics_provider.dart';
import '../../analytics/view/widgets/telemetry_history_card.dart';
import '../bloc/battery_bloc.dart';
import '../bloc/battery_event.dart';
import '../bloc/battery_state.dart';
import '../providers/battery_provider.dart';

class BatteryPage extends ConsumerStatefulWidget {
  const BatteryPage({super.key});

  @override
  ConsumerState<BatteryPage> createState() => _BatteryPageState();
}

class _BatteryPageState extends ConsumerState<BatteryPage> {
  @override
  void initState() {
    super.initState();
    ref.read(analyticsBlocProvider.bloc).add(const AnalyticsStarted());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(batteryBlocProvider);
    final analytics = ref.watch(analyticsBlocProvider);
    final bloc = ref.read(batteryBlocProvider.bloc);
    final analyticsBloc = ref.read(analyticsBlocProvider.bloc);

    if (!state.hasLoaded && state.errorMessage == null) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    final health = _batteryHealth(state);
    final accent = const Color(0xff3A9D4F);

    return AppPageBody(
      errorMessage: state.errorMessage ?? analytics.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        _BatteryOverview(state: state, health: health, accent: accent),
        const SizedBox(height: 16),
        _HistoryCollectionCard(
          isCollecting: analytics.isCollecting,
          history: analytics.history,
          accent: accent,
          onCollectionChanged: (enabled) =>
              analyticsBloc.add(AnalyticsCollectionSetRequested(enabled)),
        ),
        const SizedBox(height: 16),
        TelemetryHistoryCard(
          history: analytics.history,
          window: analytics.window,
          isCollecting: analytics.isCollecting,
          accentColor: accent,
          onWindowChanged: analyticsBloc.add,
          options: const [
            TelemetrySeriesOption(
              label: 'Charge %',
              unit: '%',
              minimumY: 0,
              maximumY: 100,
              valueOf: _batteryPercent,
            ),
            TelemetrySeriesOption(
              label: 'Battery power',
              unit: 'W',
              valueOf: _batteryPower,
              description:
                  'Battery-side charge/discharge power reported by the pack, '
                  'not CPU package or wall power. Positive values discharge; '
                  'negative values charge.',
            ),
            TelemetrySeriesOption(
              label: 'Temperature',
              unit: '°C',
              valueOf: _batteryTemperature,
              unavailableMessage:
                  'Battery temperature is not exposed by the battery driver.',
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 720
                ? (constraints.maxWidth - 14) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: width,
                  child: _BatteryDetails(state: state),
                ),
                SizedBox(
                  width: width,
                  child: _EnergyDetails(state: state),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _BatteryControls(state: state, bloc: bloc),
      ],
    );
  }
}

class _BatteryOverview extends StatelessWidget {
  const _BatteryOverview({
    required this.state,
    required this.health,
    required this.accent,
  });

  final BatteryState state;
  final double? health;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = state.batteryPercent;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Wrap(
        spacing: 24,
        runSpacing: 18,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox.square(
            dimension: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.square(
                  dimension: 78,
                  child: CircularProgressIndicator(
                    value: percent == null ? 0 : percent.clamp(0, 100) / 100,
                    strokeWidth: 9,
                    strokeCap: StrokeCap.round,
                    color: accent,
                    backgroundColor: scheme.outlineVariant,
                  ),
                ),
                Text(
                  percent == null ? '—' : '$percent%',
                  style: monoGaugeStyle(92, scheme.onSurface),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 190, maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.chargeStateLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _statusDescription(state),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _OverviewMetric(
            value: health == null ? '—' : '${health!.toStringAsFixed(0)}%',
            label: 'Health',
          ),
          _OverviewMetric(
            value: '${state.cycleCounts ?? '—'}',
            label: 'Cycles',
          ),
          _OverviewMetric(
            value: state.batteryTempC == null
                ? 'N/A'
                : '${state.batteryTempC!.toStringAsFixed(1)}°',
            label: 'Temperature',
          ),
        ],
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: monoGaugeStyle(82, scheme.onSurface).copyWith(fontSize: 20),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _HistoryCollectionCard extends StatelessWidget {
  const _HistoryCollectionCard({
    required this.isCollecting,
    required this.history,
    required this.accent,
    required this.onCollectionChanged,
  });

  final bool isCollecting;
  final List<SensorRecord> history;
  final Color accent;
  final ValueChanged<bool> onCollectionChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final description = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xff3A9D4F).withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(9),
                  child: Icon(
                    Icons.show_chart,
                    size: 20,
                    color: Color(0xff2F8443),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Collect history',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Sample sensors every 30 seconds and keep 30 days.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                onPressed: history.isEmpty ? null : () => _export(context),
                child: const Text('Export logs'),
              ),
              const SizedBox(width: 10),
              YaruSwitch(
                value: isCollecting,
                selectedColor: accent,
                onChanged: onCollectionChanged,
              ),
            ],
          );
          return constraints.maxWidth < 560
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    description,
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: description),
                    const SizedBox(width: 16),
                    actions,
                  ],
                );
        },
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final stamp = DateTime.now()
        .toIso8601String()
        .split('.')
        .first
        .replaceAll(':', '-');
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Export telemetry logs',
        fileName: 'legion-telemetry-$stamp.csv',
        bytes: sensorRecordsCsv(history),
        mimeType: 'text/csv',
      );
      if (uri != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Telemetry exported to $uri')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export telemetry: $error')),
        );
      }
    }
  }
}

class _BatteryDetails extends StatelessWidget {
  const _BatteryDetails({required this.state});

  final BatteryState state;

  @override
  Widget build(BuildContext context) => _DetailCard(
    title: 'Battery',
    rows: [
      ('Charge state', state.chargeStateLabel),
      ('Current charge', _percentLabel(state.batteryPercent)),
      ('Health', _percentLabel(_batteryHealth(state))),
      ('Charge cycles', '${state.cycleCounts ?? '—'}'),
      ('Vendor', state.manufacturer ?? '—'),
      ('Model', state.modelName ?? '—'),
      ('Serial', state.serialNumber ?? '—'),
    ],
  );
}

class _EnergyDetails extends StatelessWidget {
  const _EnergyDetails({required this.state});

  final BatteryState state;

  @override
  Widget build(BuildContext context) => _DetailCard(
    title: 'Energy',
    rows: [
      ('Voltage', _measurement(state.voltageV, 'V', 2)),
      (
        'Battery temperature',
        state.batteryTempC == null
            ? 'Not exposed by battery driver'
            : _measurement(state.batteryTempC, '°C', 1),
      ),
      (
        _batteryRateLabel(state),
        _measurement(state.batteryPowerDrawW?.abs(), 'W', 2),
      ),
      ('Remaining energy', _measurement(state.currentCapacityWh, 'Wh', 2)),
      ('Last full charge', _measurement(state.fullCapacityWh, 'Wh', 2)),
      ('Design capacity', _measurement(state.designCapacityWh, 'Wh', 2)),
    ],
  );
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 6),
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[index].$1,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      rows[index].$2,
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: monoFactStyle(scheme).copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BatteryControls extends StatelessWidget {
  const _BatteryControls({required this.state, required this.bloc});

  final BatteryState state;
  final BatteryBloc bloc;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 940
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth >= 620
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: width,
              child: _ControlTile(
                icon: YaruIcons.battery,
                title: 'Conservation mode',
                subtitle: state.batteryConservationSupported
                    ? 'Hold charge near 80%'
                    : 'Not supported on this device',
                value: state.batteryConservationEnabled ?? false,
                onChanged:
                    state.batteryConservationSupported && !state.isApplying
                    ? (enabled) =>
                          bloc.add(BatteryConservationSetRequested(enabled))
                    : null,
              ),
            ),
            SizedBox(
              width: width,
              child: _ControlTile(
                icon: YaruIcons.thunderbolt,
                title: 'Rapid charge',
                subtitle: state.rapidChargingSupported
                    ? 'Charge to full faster'
                    : 'Not supported on this device',
                value: state.rapidChargingEnabled ?? false,
                onChanged: state.rapidChargingSupported && !state.isApplying
                    ? (enabled) => bloc.add(RapidChargingSetRequested(enabled))
                    : null,
              ),
            ),
            SizedBox(
              width: width,
              child: _ControlTile(
                icon: Icons.usb,
                title: 'Always-on USB',
                subtitle: state.alwaysOnUsbEnabled == null
                    ? 'Not exposed by this system'
                    : state.alwaysOnUsbSupported
                    ? 'Charge devices while asleep'
                    : 'Charge devices while asleep · read-only',
                value: state.alwaysOnUsbEnabled ?? false,
                onChanged: state.alwaysOnUsbSupported && !state.isApplying
                    ? (enabled) => bloc.add(AlwaysOnUsbSetRequested(enabled))
                    : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ControlTile extends StatelessWidget {
  const _ControlTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xff3A9D4F).withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Icon(icon, size: 19, color: const Color(0xff2F8443)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          YaruSwitch(
            value: value,
            selectedColor: const Color(0xff3A9D4F),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

double? _batteryPercent(SensorRecord record) =>
    record.batteryPercent?.toDouble();
double? _batteryPower(SensorRecord record) => record.batteryPowerDrawW;
double? _batteryTemperature(SensorRecord record) => record.batteryTempC;

String _batteryRateLabel(BatteryState state) => switch (state.batteryCharging) {
  true => 'Charge rate',
  false => 'Discharge rate',
  null => 'Battery power',
};

double? _batteryHealth(BatteryState state) {
  final full = state.fullCapacityWh;
  final design = state.designCapacityWh;
  if (full == null || design == null || design <= 0) return null;
  return (full / design * 100).clamp(0, 100);
}

String _statusDescription(BatteryState state) {
  if (state.batteryStatus == null) return 'Battery status is unavailable.';
  final status = state.batteryStatus!.toLowerCase();
  if (status == 'not charging' && state.batteryConservationEnabled == true) {
    return 'Holding charge with battery health protection on.';
  }
  if (status == 'not charging') return 'The battery is not charging.';
  if (status == 'full') {
    return 'The battery has reached its current charge limit.';
  }
  if (status == 'charging') return 'Drawing power from the charger.';
  if (status == 'discharging') return 'Supplying power to the system.';
  return 'Battery reported “${state.batteryStatus}”.';
}

String _percentLabel(num? value) =>
    value == null ? '—' : '${value.toStringAsFixed(value is int ? 0 : 1)}%';

String _measurement(double? value, String unit, int precision) =>
    value == null ? '—' : '${value.toStringAsFixed(precision)} $unit';
