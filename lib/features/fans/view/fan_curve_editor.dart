import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/metric_text.dart';
import '../../../core/widgets/surface_card.dart';
import '../models/fan_curve.dart';

enum FanChannel {
  cpu('CPU fan'),
  gpu('GPU fan');

  const FanChannel(this.label);

  final String label;
}

class FanCurveEditor extends StatefulWidget {
  const FanCurveEditor({
    super.key,
    required this.curve,
    required this.channel,
    required this.currentTemperature,
    required this.currentRpm,
    required this.accent,
    required this.enabled,
    required this.dirty,
    required this.isApplying,
    required this.onPointChanged,
    required this.onSave,
  });

  final FanCurve curve;
  final FanChannel channel;
  final double? currentTemperature;
  final int? currentRpm;
  final Color accent;
  final bool enabled;
  final bool dirty;
  final bool isApplying;
  final void Function(int index, FanCurvePoint point) onPointChanged;
  final VoidCallback? onSave;

  @override
  State<FanCurveEditor> createState() => _FanCurveEditorState();
}

class FanCurveUnavailablePanel extends StatelessWidget {
  const FanCurveUnavailablePanel({
    super.key,
    required this.channel,
    required this.currentTemperature,
    required this.currentRpm,
    required this.accent,
  });

  final FanChannel channel;
  final double? currentTemperature;
  final int? currentRpm;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metrics = [
      _FanSummaryCard(
        title: 'Current ${channel == FanChannel.cpu ? 'CPU' : 'GPU'} fan',
        value: currentRpm == null ? '—' : '$currentRpm',
        unit: currentRpm == null ? null : 'RPM',
        subtitle: currentRpm == null
            ? 'Tachometer unavailable'
            : 'Live reading',
      ),
      _FanSummaryCard(
        title: 'Current temperature',
        value: currentTemperature == null
            ? '—'
            : '${currentTemperature!.round()}°C',
        subtitle: channel == FanChannel.cpu ? 'CPU package' : 'GPU sensor',
        accent: accent,
      ),
    ];

    return Theme(
      data: theme.copyWith(colorScheme: scheme.copyWith(primary: accent)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(YaruIcons.information, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Custom curve editing is not available',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'The controller did not provide a usable fan curve. Live readings remain available.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 720) {
                return Column(
                  children: [
                    for (var i = 0; i < metrics.length; i++) ...[
                      metrics[i],
                      if (i != metrics.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < metrics.length; i++) ...[
                    Expanded(child: metrics[i]),
                    if (i != metrics.length - 1) const SizedBox(width: 12),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FanCurveEditorState extends State<FanCurveEditor> {
  int _selectedIndex = 0;
  int? _draggingIndex;
  Offset? _dragPosition;

  bool get _canEdit => widget.enabled && !widget.isApplying;

  double get _maxRpm =>
      (widget.channel == FanChannel.cpu
              ? widget.curve.fan1MaxRpm
              : widget.curve.fan2MaxRpm)
          .toDouble();

  int _temperature(FanCurvePoint point) => widget.channel == FanChannel.cpu
      ? point.cpuUpperTemp
      : point.gpuUpperTemp;

  int _rpm(FanCurvePoint point) =>
      widget.channel == FanChannel.cpu ? point.fan1Rpm : point.fan2Rpm;

  int _lowerTemperature(FanCurvePoint point) => widget.channel == FanChannel.cpu
      ? point.cpuLowerTemp
      : point.gpuLowerTemp;

  FanCurvePoint _updatePoint(
    FanCurvePoint point, {
    int? temperature,
    int? rpm,
  }) {
    return widget.channel == FanChannel.cpu
        ? point.copyWith(cpuUpperTemp: temperature, fan1Rpm: rpm)
        : point.copyWith(gpuUpperTemp: temperature, fan2Rpm: rpm);
  }

  int _boundedTemperature(int index, int value) {
    final points = widget.curve.points;
    var minimum = _lowerTemperature(points[index]).clamp(0, 100);
    if (index > 0) {
      final previous = _temperature(points[index - 1]).clamp(0, 100);
      if (previous > minimum) minimum = previous;
    }
    var maximum = 100;
    if (index < points.length - 1) {
      maximum = _temperature(points[index + 1]).clamp(0, 100);
    }
    if (minimum > maximum) return _temperature(points[index]);
    return value.clamp(minimum, maximum);
  }

  int _boundedRpm(int index, int value) {
    final points = widget.curve.points;
    final maximumRpm = _maxRpm.round();
    final minimum = index == 0
        ? 0
        : _rpm(points[index - 1]).clamp(0, maximumRpm);
    final maximum = index == points.length - 1
        ? maximumRpm
        : _rpm(points[index + 1]).clamp(0, maximumRpm);
    if (minimum > maximum) return _rpm(points[index]);
    return value.clamp(minimum, maximum);
  }

  List<FlSpot> _spots() => [
    for (final point in widget.curve.points)
      FlSpot(_temperature(point).toDouble(), _rpm(point) / _maxRpm * 100),
  ];

  void _selectNearest(Offset position, Size size) {
    if (widget.curve.points.isEmpty) return;
    var nearest = 0;
    var distance = double.infinity;
    for (var i = 0; i < widget.curve.points.length; i++) {
      final point = widget.curve.points[i];
      final pointPosition = Offset(
        _temperature(point) / 100 * size.width,
        (1 - _rpm(point) / _maxRpm) * size.height,
      );
      final candidate = (pointPosition - position).distanceSquared;
      if (candidate < distance) {
        nearest = i;
        distance = candidate;
      }
    }
    setState(() {
      _selectedIndex = nearest;
      _draggingIndex = nearest;
    });
  }

  void _updateFromPosition(Offset position, Size size) {
    final index = _draggingIndex;
    if (!_canEdit || index == null || size.isEmpty) return;
    final temperature = _boundedTemperature(
      index,
      (position.dx / size.width * 100).round(),
    );
    final percent = ((1 - position.dy / size.height) * 100).clamp(0, 100);
    final rpm = _boundedRpm(index, (percent * _maxRpm / 100).round());
    final point = widget.curve.points[index];
    widget.onPointChanged(
      index,
      _updatePoint(point, temperature: temperature, rpm: rpm),
    );
    setState(() {
      _dragPosition = Offset(
        position.dx.clamp(0, size.width),
        position.dy.clamp(0, size.height),
      );
    });
  }

  void _endDrag() {
    setState(() {
      _draggingIndex = null;
      _dragPosition = null;
    });
  }

  @override
  void didUpdateWidget(covariant FanCurveEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex >= widget.curve.points.length) {
      _selectedIndex = widget.curve.points.isEmpty
          ? 0
          : widget.curve.points.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accentScheme = scheme.copyWith(primary: widget.accent);

    return Theme(
      data: theme.copyWith(colorScheme: accentScheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SurfaceCard(
            padding: const EdgeInsets.all(18),
            child: widget.curve.points.isEmpty
                ? const SizedBox(
                    height: 300,
                    child: Center(
                      child: Text('This fan curve has no editable points.'),
                    ),
                  )
                : _buildChart(context),
          ),
          const SizedBox(height: 12),
          if (widget.curve.points.isNotEmpty) _buildSummaryCards(context),
          if (widget.curve.points.isNotEmpty) ...[
            const SizedBox(height: 12),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: YaruExpandable(
                key: const ValueKey('fan-precise-controls'),
                isExpanded: false,
                expandButtonPosition: YaruExpandableButtonPosition.end,
                header: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text('Precise point controls'),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _buildPointControls(context),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: _SaveRow(
                dirty: widget.dirty,
                isApplying: widget.isApplying,
                accent: widget.accent,
                onSave: widget.dirty && !widget.isApplying
                    ? widget.onSave
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentTemperature = widget.currentTemperature?.clamp(0, 100);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final chartHeight = compact ? 274.0 : 326.0;
        const plotLeft = 42.0;
        const plotRight = 14.0;
        const plotTop = 30.0;
        const plotBottom = 42.0;

        return Semantics(
          label:
              '${widget.channel.label} curve. Drag points with the mouse or use the point controls below.',
          child: Container(
            height: chartHeight,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: scheme.onSurface.withValues(alpha: 0.08),
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 10,
                  top: 8,
                  child: Text(
                    'Fan speed %',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                Positioned(
                  left: 4,
                  top: plotTop,
                  bottom: plotBottom,
                  width: 32,
                  child: const _YAxisLabels(),
                ),
                Positioned(
                  left: plotLeft,
                  right: plotRight,
                  top: plotTop,
                  bottom: plotBottom,
                  child: LayoutBuilder(
                    builder: (context, plotConstraints) {
                      final plotSize = plotConstraints.biggest;
                      return GestureDetector(
                        key: const ValueKey('fan-curve-chart-plot'),
                        behavior: HitTestBehavior.opaque,
                        onPanStart: _canEdit
                            ? (details) {
                                _selectNearest(details.localPosition, plotSize);
                                _updateFromPosition(
                                  details.localPosition,
                                  plotSize,
                                );
                              }
                            : null,
                        onPanUpdate: _canEdit
                            ? (details) => _updateFromPosition(
                                details.localPosition,
                                plotSize,
                              )
                            : null,
                        onPanEnd: _canEdit ? (_) => _endDrag() : null,
                        onPanCancel: _canEdit ? _endDrag : null,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: LineChart(
                                _chartData(
                                  scheme,
                                  currentTemperature?.toDouble(),
                                ),
                                duration: Duration.zero,
                              ),
                            ),
                            if (_dragPosition case final position?)
                              _DragTooltip(
                                position: position,
                                plotSize: plotSize,
                                temperature: _temperature(
                                  widget.curve.points[_selectedIndex],
                                ),
                                percent:
                                    (_rpm(widget.curve.points[_selectedIndex]) /
                                            _maxRpm *
                                            100)
                                        .round(),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const Positioned(
                  left: plotLeft,
                  right: plotRight,
                  bottom: 19,
                  child: _XAxisLabels(),
                ),
                Positioned(
                  right: plotRight,
                  bottom: 3,
                  child: Text(
                    'Temperature ->',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  LineChartData _chartData(ColorScheme scheme, double? currentTemperature) {
    return LineChartData(
      minX: 0,
      maxX: 100,
      minY: 0,
      maxY: 100,
      clipData: const FlClipData.all(),
      backgroundColor: scheme.surface,
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(
        show: true,
        border: Border(
          left: BorderSide(color: scheme.onSurface.withValues(alpha: 0.18)),
          bottom: BorderSide(color: scheme.onSurface.withValues(alpha: 0.18)),
        ),
      ),
      gridData: FlGridData(
        show: true,
        horizontalInterval: 25,
        verticalInterval: 20,
        getDrawingHorizontalLine: (_) => FlLine(
          color: scheme.onSurface.withValues(alpha: 0.08),
          strokeWidth: 1,
        ),
        getDrawingVerticalLine: (_) => FlLine(
          color: scheme.onSurface.withValues(alpha: 0.06),
          strokeWidth: 1,
        ),
      ),
      extraLinesData: currentTemperature == null
          ? const ExtraLinesData()
          : ExtraLinesData(
              verticalLines: [
                VerticalLine(
                  x: currentTemperature,
                  color: const Color(0xFFEC5F2A),
                  strokeWidth: 1.5,
                  dashArray: const [5, 4],
                  label: VerticalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    padding: const EdgeInsets.only(left: 5, bottom: 4),
                    style: const TextStyle(
                      color: Color(0xFFEC5F2A),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    labelResolver: (_) => '${currentTemperature.round()}°C',
                  ),
                ),
              ],
            ),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(
          spots: _spots(),
          color: widget.accent,
          barWidth: 3,
          isCurved: false,
          isStrokeCapRound: true,
          isStrokeJoinRound: true,
          belowBarData: BarAreaData(
            show: true,
            color: widget.accent.withValues(alpha: 0.11),
          ),
          dotData: FlDotData(
            show: true,
            getDotPainter: (_, _, _, index) {
              final active = index == _selectedIndex || index == _draggingIndex;
              return FlDotCirclePainter(
                radius: active ? 6 : 4.5,
                color: active ? widget.accent : scheme.surface,
                strokeColor: active ? scheme.surface : widget.accent,
                strokeWidth: active ? 2.5 : 2,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards(BuildContext context) {
    final point = widget.curve.points[_selectedIndex];
    final temperature = _temperature(point);
    final hysteresis = (temperature - _lowerTemperature(point)).clamp(0, 100);
    final currentTemperature = widget.currentTemperature;
    final cards = [
      _FanSummaryCard(
        title:
            'Current ${widget.channel == FanChannel.cpu ? 'CPU' : 'GPU'} fan',
        value: widget.currentRpm == null ? '—' : '${widget.currentRpm}',
        unit: widget.currentRpm == null ? null : 'RPM',
        subtitle: currentTemperature == null
            ? 'Temperature unavailable'
            : '${currentTemperature.round()}°C now',
      ),
      _FanSummaryCard(
        title: 'Hysteresis',
        value: '$hysteresis°C',
        subtitle: 'Ramp ${point.accel}/${point.decel}',
        accent: widget.accent,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i != cards.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i != cards.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _buildPointControls(BuildContext context) {
    final point = widget.curve.points[_selectedIndex];
    final temperature = _temperature(point);
    final rpm = _rpm(point);
    final percent = rpm / _maxRpm * 100;
    final hysteresis = (temperature - _lowerTemperature(point)).clamp(0, 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Selected point',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Wrap(
              key: const ValueKey('fan-point-selector'),
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < widget.curve.points.length; i++)
                  ChoiceChip(
                    label: Text('${i + 1}'),
                    selected: _selectedIndex == i,
                    onSelected: _canEdit
                        ? (_) => setState(() => _selectedIndex = i)
                        : null,
                  ),
              ],
            ),
            Text(
              'Hysteresis $hysteresis°C  ·  Ramp ${point.accel}/${point.decel}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final controls = [
              _CurveValueControl(
                controlKey: const ValueKey('fan-temperature-slider'),
                label: 'Temperature',
                valueLabel: '$temperature°C',
                value: temperature.toDouble(),
                enabled: _canEdit,
                onChanged: (value) => widget.onPointChanged(
                  _selectedIndex,
                  _updatePoint(
                    point,
                    temperature: _boundedTemperature(
                      _selectedIndex,
                      value.round(),
                    ),
                  ),
                ),
              ),
              _CurveValueControl(
                controlKey: const ValueKey('fan-speed-slider'),
                label: 'Fan speed',
                valueLabel: '${percent.round()}%  ·  $rpm RPM',
                value: percent,
                enabled: _canEdit,
                onChanged: (value) => widget.onPointChanged(
                  _selectedIndex,
                  _updatePoint(
                    point,
                    rpm: _boundedRpm(
                      _selectedIndex,
                      (value * _maxRpm / 100).round(),
                    ),
                  ),
                ),
              ),
            ];
            if (constraints.maxWidth < 620) {
              return Column(
                children: [
                  controls.first,
                  const SizedBox(height: 8),
                  controls.last,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: controls.first),
                const SizedBox(width: 20),
                Expanded(child: controls.last),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FanSummaryCard extends StatelessWidget {
  const _FanSummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    this.unit,
    this.accent,
  });

  final String title;
  final String value;
  final String subtitle;
  final String? unit;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    Text(
                      value,
                      style: monoBarStyle(
                        accent ?? scheme.onSurface,
                      ).copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                    if (unit != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(unit!, style: monoMetaStyle(scheme)),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveRow extends StatelessWidget {
  const _SaveRow({
    required this.dirty,
    required this.isApplying,
    required this.accent,
    required this.onSave,
  });

  final bool dirty;
  final bool isApplying;
  final Color accent;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        Text(
          dirty
              ? 'Unsaved changes · review the curve before applying.'
              : 'The hardware curve is up to date.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: dirty ? accent : null),
        ),
        FilledButton.icon(
          key: const ValueKey('fan-curve-save'),
          onPressed: onSave,
          icon: isApplying
              ? const SizedBox.square(
                  dimension: 16,
                  child: YaruCircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Apply to hardware'),
        ),
      ],
    );
  }
}

class _CurveValueControl extends StatelessWidget {
  const _CurveValueControl({
    required this.controlKey,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final Key controlKey;
  final String label;
  final String valueLabel;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            Text(valueLabel, style: monoBarStyle(scheme.onSurface)),
          ],
        ),
        Slider(
          key: controlKey,
          value: value.clamp(0, 100),
          min: 0,
          max: 100,
          divisions: 100,
          label: valueLabel,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}

class _YAxisLabels extends StatelessWidget {
  const _YAxisLabels();

  @override
  Widget build(BuildContext context) {
    final style = monoMetaStyle(Theme.of(context).colorScheme);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final value in const [100, 75, 50, 25, 0])
          Text('$value', style: style),
      ],
    );
  }
}

class _XAxisLabels extends StatelessWidget {
  const _XAxisLabels();

  @override
  Widget build(BuildContext context) {
    final style = monoMetaStyle(Theme.of(context).colorScheme);
    return LayoutBuilder(
      builder: (context, constraints) {
        final values = constraints.maxWidth < 220
            ? const [0, 50, 100]
            : const [0, 20, 40, 60, 80, 100];
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [for (final value in values) Text('$value°', style: style)],
        );
      },
    );
  }
}

class _DragTooltip extends StatelessWidget {
  const _DragTooltip({
    required this.position,
    required this.plotSize,
    required this.temperature,
    required this.percent,
  });

  final Offset position;
  final Size plotSize;
  final int temperature;
  final int percent;

  @override
  Widget build(BuildContext context) {
    const width = 96.0;
    const height = 34.0;
    final left = (position.dx - width / 2)
        .clamp(0.0, plotSize.width - width)
        .toDouble();
    final top = (position.dy - height - 10)
        .clamp(0.0, plotSize.height - height)
        .toDouble();
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.inverseSurface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              '$temperature°  ·  $percent%',
              style: monoBarStyle(
                Theme.of(context).colorScheme.onInverseSurface,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}
