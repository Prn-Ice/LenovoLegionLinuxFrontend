import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/fans_bloc.dart';
import '../bloc/fans_event.dart';
import '../bloc/fans_state.dart';
import '../models/fan_curve.dart';
import '../providers/fans_provider.dart';

class FansPage extends ConsumerWidget {
  const FansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fansBlocProvider);
    final bloc = ref.read(fansBlocProvider.bloc);

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    return AppPageBody(
      title: 'Fans',
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        // Action row
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    state.maximumFanSpeedEnabled == null || state.isApplying
                    ? null
                    : () async {
                        final enabled = !(state.maximumFanSpeedEnabled ?? false);
                        final confirmed = await confirmPrivilegedAction(
                          context,
                          title: 'Toggle maximum fan speed',
                          message:
                              'This action uses privileged access and may prompt for authentication.',
                          confirmLabel: 'Apply',
                        );
                        if (!context.mounted || !confirmed) return;
                        bloc.add(MaximumFanSpeedSetRequested(enabled));
                      },
                icon: const Icon(YaruIcons.gears),
                label: Text(
                  (state.maximumFanSpeedEnabled ?? false)
                      ? 'Max Fan: On'
                      : 'Max Fan Speed',
                ),
                style: (state.maximumFanSpeedEnabled ?? false)
                    ? OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.primary,
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed:
                    state.availablePresets.isEmpty || state.isApplying
                    ? null
                    : () => _showPresetDialog(context, state, bloc),
                icon: const Icon(Icons.tune),
                label: const Text('Apply Preset'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Fan Curve card
        AppControlCard(
          icon: Icons.show_chart,
          title: 'Fan Curve',
          description:
              'Custom 10-point temperature/RPM curve. '
              'Lower temp = hysteresis threshold; Upper temp = trigger threshold.',
          children: [
            if (state.fanCurve == null)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Fan curve editor'),
                subtitle: Text('Unavailable — hwmon driver not detected.'),
              )
            else ...[
              const PrivilegedActionNotice(),
              const SizedBox(height: 8),
              _FanCurveChart(
                curve: state.fanCurve!,
                enabled: !state.isApplying,
                onPointChanged: (index, point) =>
                    bloc.add(FanCurvePointUpdated(index: index, point: point)),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: (state.fanCurveDirty && !state.isApplying)
                    ? () async {
                        final confirmed = await confirmPrivilegedAction(
                          context,
                          title: 'Apply fan curve',
                          message:
                              'Writing a custom fan curve requires privileged access and may prompt for authentication.',
                          confirmLabel: 'Apply',
                        );
                        if (!context.mounted || !confirmed) {
                          return;
                        }
                        bloc.add(const FanCurveSaveRequested());
                      }
                    : null,
                icon: state.isApplying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: YaruCircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Apply to hardware'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        // Fan Controls card
        AppControlCard(
          icon: YaruIcons.gears,
          title: 'Fan Controls',
          children: [
            const PrivilegedActionNotice(),
            const SizedBox(height: 8),
            AppSwitchTile(
              value: state.miniFanCurveEnabled ?? false,
              onChanged:
                  (state.miniFanCurveEnabled != null && !state.isApplying)
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Set mini fan curve',
                        message:
                            'This action uses privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(MiniFanCurveSetRequested(enabled));
                    }
                  : null,
              title: 'Mini fan curve',
              subtitle: boolEnabledLabel(state.miniFanCurveEnabled),
            ),
            AppSwitchTile(
              value: state.lockFanControllerEnabled ?? false,
              onChanged:
                  (state.lockFanControllerEnabled != null && !state.isApplying)
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Set lock fan controller',
                        message:
                            'This action uses privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(LockFanControllerSetRequested(enabled));
                    }
                  : null,
              title: 'Lock fan controller',
              subtitle: boolEnabledLabel(state.lockFanControllerEnabled),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppRefreshButton(
          isBusy: state.isLoading,
          onPressed: state.isApplying
              ? null
              : () => bloc.add(const FansRefreshRequested()),
        ),
      ],
    );
  }
}

Future<void> _showPresetDialog(
  BuildContext context,
  FansState state,
  FansBloc bloc,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const YaruDialogTitleBar(title: Text('Select Fan Preset')),
      titlePadding: EdgeInsets.zero,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: state.availablePresets.map((preset) {
          final isRecommended = preset == state.recommendedPreset;
          return ListTile(
            title: Text(preset),
            subtitle: isRecommended
                ? const Text('Recommended for current context')
                : null,
            trailing: isRecommended
                ? Icon(
                    YaruIcons.star_filled,
                    color: Theme.of(dialogContext).colorScheme.primary,
                  )
                : null,
            onTap: () async {
              Navigator.of(dialogContext).pop();
              bloc.add(FansPresetSelectionChanged(preset));
              final confirmed = await confirmPrivilegedAction(
                context,
                title: 'Apply fan preset',
                message: 'Applying fan presets requires privileged access.',
                confirmLabel: 'Apply preset',
              );
              if (!context.mounted || !confirmed) return;
              bloc.add(const FansApplySelectedPresetRequested());
            },
          );
        }).toList(),
      ),
    ),
  );
}

class _FanCurveChart extends StatefulWidget {
  const _FanCurveChart({
    required this.curve,
    required this.enabled,
    required this.onPointChanged,
  });

  final FanCurve curve;
  final bool enabled;
  final void Function(int index, FanCurvePoint point) onPointChanged;

  @override
  State<_FanCurveChart> createState() => _FanCurveChartState();
}

class _FanCurveChartState extends State<_FanCurveChart> {
  static const _maxRpm = 5000.0;
  int? _draggingIndex;

  List<FlSpot> _fan1Spots() => List.generate(
        10,
        (i) => FlSpot(
          widget.curve.points[i].cpuUpperTemp.toDouble(),
          widget.curve.points[i].fan1Rpm.toDouble(),
        ),
      );

  List<FlSpot> _fan2Spots() => List.generate(
        10,
        (i) => FlSpot(
          widget.curve.points[i].cpuUpperTemp.toDouble(),
          widget.curve.points[i].fan2Rpm.toDouble(),
        ),
      );

  void _handlePanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    if (!widget.enabled) return;
    final chartWidth = constraints.maxWidth;
    final chartHeight = constraints.maxHeight;
    final x = details.localPosition.dx / chartWidth * 100;
    final y = (1 - details.localPosition.dy / chartHeight) * _maxRpm;

    if (_draggingIndex != null) {
      final point = widget.curve.points[_draggingIndex!];
      // Drag controls fan1 only; fan2 is a separate hardware value displayed
      // for reference. TODO: account for fl_chart axis insets in coordinate mapping.
      widget.onPointChanged(
        _draggingIndex!,
        point.copyWith(
          cpuUpperTemp: x.round().clamp(0, 100),
          fan1Rpm: y.round().clamp(0, _maxRpm.round()),
        ),
      );
    }
  }

  void _handlePanStart(DragStartDetails details, BoxConstraints constraints) {
    if (!widget.enabled) return;
    final chartWidth = constraints.maxWidth;
    final x = details.localPosition.dx / chartWidth * 100;
    // Find nearest point
    int nearest = 0;
    double minDist = double.maxFinite;
    for (var i = 0; i < 10; i++) {
      final dist =
          (widget.curve.points[i].cpuUpperTemp.toDouble() - x).abs();
      if (dist < minDist) {
        minDist = dist;
        nearest = i;
      }
    }
    setState(() => _draggingIndex = nearest);
  }

  void _handlePanEnd(DragEndDetails _) => setState(() => _draggingIndex = null);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanStart: (d) => _handlePanStart(d, constraints),
          onPanUpdate: (d) => _handlePanUpdate(d, constraints),
          onPanEnd: _handlePanEnd,
          child: SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 100,
                minY: 0,
                maxY: _maxRpm,
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: true),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Text('Temperature (°C)'),
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 20,
                      getTitlesWidget: (v, _) => Text('${v.round()}'),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    axisNameWidget: const Text('RPM'),
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1000,
                      getTitlesWidget: (v, _) => Text('${v.round()}'),
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: _fan1Spots(),
                    color: scheme.primary,
                    dotData: const FlDotData(show: true),
                    isCurved: false,
                  ),
                  LineChartBarData(
                    spots: _fan2Spots(),
                    color: scheme.secondary,
                    dotData: const FlDotData(show: true),
                    isCurved: false,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
