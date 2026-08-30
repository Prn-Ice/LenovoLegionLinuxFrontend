import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../../core/widgets/surface_card.dart';
import '../../bloc/analytics_event.dart';
import '../../bloc/analytics_state.dart';
import '../../models/sensor_record.dart';

class TelemetrySeriesOption {
  const TelemetrySeriesOption({
    required this.label,
    required this.valueOf,
    required this.unit,
    this.minimumY,
    this.maximumY,
    this.description,
    this.unavailableMessage,
  });

  final String label;
  final double? Function(SensorRecord record) valueOf;
  final String unit;
  final double? minimumY;
  final double? maximumY;
  final String? description;
  final String? unavailableMessage;
}

class TelemetryHistoryCard extends StatefulWidget {
  const TelemetryHistoryCard({
    super.key,
    required this.history,
    required this.window,
    required this.options,
    required this.onWindowChanged,
    required this.isCollecting,
    required this.accentColor,
  });

  final List<SensorRecord> history;
  final AnalyticsTimeWindow window;
  final List<TelemetrySeriesOption> options;
  final ValueChanged<AnalyticsWindowChanged> onWindowChanged;
  final bool isCollecting;
  final Color accentColor;

  @override
  State<TelemetryHistoryCard> createState() => _TelemetryHistoryCardState();
}

class _TelemetryHistoryCardState extends State<TelemetryHistoryCard> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final option = widget.options[_selectedIndex];
    final availableSpots = <FlSpot>[
      for (var index = 0; index < widget.history.length; index++)
        if (option.valueOf(widget.history[index]) case final double value)
          if (value.isFinite) FlSpot(index.toDouble(), value),
    ];
    final spots = _downsample(availableSpots);
    final values = spots.map((spot) => spot.y).toList();
    final scheme = Theme.of(context).colorScheme;

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final controls = [
                _SeriesPicker(
                  options: widget.options,
                  selectedIndex: _selectedIndex,
                  compact: constraints.maxWidth < 560,
                  accentColor: widget.accentColor,
                  onSelected: (index) => setState(() => _selectedIndex = index),
                ),
                _TimeWindowPicker(
                  window: widget.window,
                  accentColor: widget.accentColor,
                  onSelected: (window) =>
                      widget.onWindowChanged(AnalyticsWindowChanged(window)),
                ),
              ];
              return constraints.maxWidth < 560
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        controls.first,
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: controls.last,
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: controls,
                    );
            },
          ),
          if (option.description != null) ...[
            const SizedBox(height: 10),
            Text(
              option.description!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 190,
            child: spots.length < 2
                ? Center(
                    child: Text(
                      widget.isCollecting
                          ? option.unavailableMessage ??
                                'History will appear after two samples.'
                          : 'History collection is paused.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minX: spots.first.x,
                      maxX: spots.last.x,
                      minY: option.minimumY ?? _lowerBound(values),
                      maxY: option.maximumY ?? _upperBound(values),
                      lineTouchData: LineTouchData(
                        getTouchedSpotIndicator: (barData, spotIndexes) => [
                          for (final _ in spotIndexes)
                            TouchedSpotIndicatorData(
                              FlLine(
                                color: widget.accentColor.withValues(
                                  alpha: 0.45,
                                ),
                                strokeWidth: 1,
                              ),
                              FlDotData(
                                show: true,
                                getDotPainter: (_, _, _, _) =>
                                    FlDotCirclePainter(
                                      radius: 4,
                                      color: widget.accentColor,
                                      strokeWidth: 2,
                                      strokeColor: scheme.surface,
                                    ),
                              ),
                            ),
                        ],
                        touchTooltipData: LineTouchTooltipData(
                          tooltipBorderRadius: BorderRadius.circular(8),
                          tooltipPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          tooltipMargin: 10,
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipColor: (_) => scheme.inverseSurface,
                          getTooltipItems: (touchedSpots) => [
                            for (final spot in touchedSpots)
                              LineTooltipItem(
                                '${spot.y.toStringAsFixed(1)} ${option.unit}\n'
                                '${_timeLabel(widget.history[spot.x.round()].timestamp)}',
                                TextStyle(
                                  color: scheme.onInverseSurface,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                          ],
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            interval: _bottomTitleInterval(spots),
                            getTitlesWidget: (value, meta) => SideTitleWidget(
                              meta: meta,
                              child: Text(
                                _axisTimeLabel(
                                  widget.history[value.round()].timestamp,
                                  widget.window,
                                ),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 42,
                            getTitlesWidget: (value, meta) => Text(
                              value.toStringAsFixed(0),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: scheme.outlineVariant.withValues(alpha: 0.55),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          curveSmoothness: 0.25,
                          color: widget.accentColor,
                          barWidth: 2.2,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: widget.accentColor.withValues(alpha: 0.09),
                          ),
                        ),
                      ],
                    ),
                    duration: Duration.zero,
                  ),
          ),
        ],
      ),
    );
  }

  double _lowerBound(List<double> values) {
    final minimum = values.reduce((a, b) => a < b ? a : b);
    return minimum > 0 ? 0 : minimum * 1.1;
  }

  double _upperBound(List<double> values) {
    final maximum = values.reduce((a, b) => a > b ? a : b);
    return maximum <= 0 ? 1 : maximum * 1.15;
  }

  List<FlSpot> _downsample(List<FlSpot> spots) {
    const maximumPoints = 720;
    if (spots.length <= maximumPoints) return spots;
    final stride = (spots.length / maximumPoints).ceil();
    final sampled = [
      for (var index = 0; index < spots.length; index += stride) spots[index],
    ];
    if (sampled.last != spots.last) sampled.add(spots.last);
    return sampled;
  }

  double _bottomTitleInterval(List<FlSpot> spots) {
    final range = spots.last.x - spots.first.x;
    return range <= 4 ? 1 : range / 4;
  }
}

class _SeriesPicker extends StatelessWidget {
  const _SeriesPicker({
    required this.options,
    required this.selectedIndex,
    required this.compact,
    required this.accentColor,
    required this.onSelected,
  });

  final List<TelemetrySeriesOption> options;
  final int selectedIndex;
  final bool compact;
  final Color accentColor;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _AccentCheckboxTheme(
        accentColor: accentColor,
        child: YaruPopupMenuButton<int>(
          initialValue: selectedIndex,
          constraints: const BoxConstraints(minWidth: 180),
          itemBuilder: (context) => [
            for (var index = 0; index < options.length; index++)
              YaruCheckedPopupMenuItem(
                value: index,
                checked: index == selectedIndex,
                child: Text(options[index].label),
              ),
          ],
          onSelected: onSelected,
          child: Text(options[selectedIndex].label),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return SegmentedButton<int>(
      showSelectedIcon: false,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accentColor.withValues(alpha: 0.18)
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accentColor
              : scheme.onSurfaceVariant,
        ),
      ),
      segments: [
        for (var index = 0; index < options.length; index++)
          ButtonSegment(value: index, label: Text(options[index].label)),
      ],
      selected: {selectedIndex},
      onSelectionChanged: (selection) => onSelected(selection.first),
    );
  }
}

class _TimeWindowPicker extends StatelessWidget {
  const _TimeWindowPicker({
    required this.window,
    required this.accentColor,
    required this.onSelected,
  });

  final AnalyticsTimeWindow window;
  final Color accentColor;
  final ValueChanged<AnalyticsTimeWindow> onSelected;

  @override
  Widget build(BuildContext context) => _AccentCheckboxTheme(
    accentColor: accentColor,
    child: YaruPopupMenuButton<AnalyticsTimeWindow>(
      initialValue: window,
      constraints: const BoxConstraints(minWidth: 160),
      itemBuilder: (context) => [
        for (final value in AnalyticsTimeWindow.values)
          YaruCheckedPopupMenuItem(
            value: value,
            checked: value == window,
            child: Text(_windowLabel(value)),
          ),
      ],
      onSelected: onSelected,
      child: Text(_windowLabel(window)),
    ),
  );
}

class _AccentCheckboxTheme extends StatelessWidget {
  const _AccentCheckboxTheme({required this.accentColor, required this.child});

  final Color accentColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final checkmarkColor =
        ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
        ? Colors.white
        : const Color(0xff102A43);
    Color? selectedColor(Set<WidgetState> states) =>
        states.contains(WidgetState.selected) ? accentColor : null;

    return YaruCheckboxTheme(
      data: YaruCheckboxTheme.of(context).copyWith(
        color: WidgetStateProperty.resolveWith(selectedColor),
        borderColor: WidgetStateProperty.resolveWith(selectedColor),
        checkmarkColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? checkmarkColor : null,
        ),
      ),
      child: child,
    );
  }
}

String _windowLabel(AnalyticsTimeWindow window) => switch (window) {
  AnalyticsTimeWindow.lastHour => 'Last hour',
  AnalyticsTimeWindow.last6h => 'Last 6 hours',
  AnalyticsTimeWindow.last24h => 'Last 24 hours',
  AnalyticsTimeWindow.last7d => 'Last 7 days',
  AnalyticsTimeWindow.last30d => 'Last 30 days',
};

String _timeLabel(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

String _axisTimeLabel(DateTime time, AnalyticsTimeWindow window) {
  if (window.duration <= const Duration(hours: 24)) return _timeLabel(time);
  return '${time.month}/${time.day}';
}
