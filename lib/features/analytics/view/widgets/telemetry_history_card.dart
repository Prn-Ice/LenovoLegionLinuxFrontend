import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

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
  });

  final String label;
  final double? Function(SensorRecord record) valueOf;
  final String unit;
  final double? minimumY;
  final double? maximumY;
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
                  onSelected: (index) => setState(() => _selectedIndex = index),
                ),
                DropdownButton<AnalyticsTimeWindow>(
                  value: widget.window,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(10),
                  items: [
                    for (final window in AnalyticsTimeWindow.values)
                      DropdownMenuItem(
                        value: window,
                        child: Text('Last ${window.label}'),
                      ),
                  ],
                  onChanged: (window) {
                    if (window != null) {
                      widget.onWindowChanged(AnalyticsWindowChanged(window));
                    }
                  },
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
          const SizedBox(height: 14),
          SizedBox(
            height: 190,
            child: spots.length < 2
                ? Center(
                    child: Text(
                      widget.isCollecting
                          ? 'History will appear after two samples.'
                          : 'History collection is paused.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minY: option.minimumY ?? _lowerBound(values),
                      maxY: option.maximumY ?? _upperBound(values),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (spots) => [
                            for (final spot in spots)
                              LineTooltipItem(
                                '${spot.y.toStringAsFixed(1)} ${option.unit}',
                                TextStyle(
                                  color: scheme.onInverseSurface,
                                  fontWeight: FontWeight.w600,
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
                        bottomTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
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
}

class _SeriesPicker extends StatelessWidget {
  const _SeriesPicker({
    required this.options,
    required this.selectedIndex,
    required this.compact,
    required this.onSelected,
  });

  final List<TelemetrySeriesOption> options;
  final int selectedIndex;
  final bool compact;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return DropdownButtonFormField<int>(
        initialValue: selectedIndex,
        decoration: const InputDecoration(isDense: true),
        items: [
          for (var index = 0; index < options.length; index++)
            DropdownMenuItem(value: index, child: Text(options[index].label)),
        ],
        onChanged: (index) {
          if (index != null) onSelected(index);
        },
      );
    }

    return SegmentedButton<int>(
      showSelectedIcon: false,
      segments: [
        for (var index = 0; index < options.length; index++)
          ButtonSegment(value: index, label: Text(options[index].label)),
      ],
      selected: {selectedIndex},
      onSelectionChanged: (selection) => onSelected(selection.first),
    );
  }
}
