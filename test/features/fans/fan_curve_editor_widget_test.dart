import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/fans/models/fan_curve.dart';
import 'package:legion_frontend/features/fans/view/fan_curve_editor.dart';
import 'package:yaru/yaru.dart';

FanCurve _curve() => FanCurve(
  name: 'widget-test',
  fan1MaxRpm: 5000,
  fan2MaxRpm: 5000,
  points: List.generate(10, (index) {
    final cpuUpper = 20 + index * 7;
    final gpuUpper = 25 + index * 7;
    return FanCurvePoint(
      fan1Rpm: 500 + index * 350,
      fan2Rpm: 800 + index * 400,
      cpuLowerTemp: cpuUpper - 3,
      cpuUpperTemp: cpuUpper,
      gpuLowerTemp: gpuUpper - 4,
      gpuUpperTemp: gpuUpper,
      icLowerTemp: 30 + index,
      icUpperTemp: 35 + index,
      accel: 4 + index,
      decel: 14 + index,
    );
  }),
);

void main() {
  testWidgets('lays out without overflow at compact width', (tester) async {
    await _pumpEditor(tester, width: 320, dirty: true);

    expect(tester.takeException(), isNull);
    expect(find.text('Current CPU fan speed'), findsOneWidget);
    await _expandPreciseControls(tester);
    expect(find.byKey(const ValueKey('fan-point-selector')), findsOneWidget);
  });

  testWidgets('lays out without overflow at wide width', (tester) async {
    await _pumpEditor(tester, width: 1000);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('fan-curve-chart-plot')), findsOneWidget);
  });

  testWidgets('GPU edits preserve unrelated point fields', (tester) async {
    FanCurvePoint? changedPoint;
    final original = _curve().points[8];
    await _pumpEditor(
      tester,
      width: 800,
      channel: FanChannel.gpu,
      onPointChanged: (_, point) => changedPoint = point,
    );

    await _expandPreciseControls(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('fan-point-selector')),
        matching: find.text('9'),
      ),
    );
    await tester.pump();
    expect(find.text('81°C'), findsWidgets);
    expect(find.textContaining('4000 RPM'), findsOneWidget);

    final temperatureSlider = tester.widget<Slider>(
      find.byKey(const ValueKey('fan-temperature-slider')),
    );
    temperatureSlider.onChanged!(82);
    await tester.pump();
    expect(
      changedPoint,
      original.copyWith(gpuUpperTemp: 82),
      reason:
          'GPU temperature edits must preserve both fan RPMs and all fields',
    );

    final speedSlider = tester.widget<Slider>(
      find.byKey(const ValueKey('fan-speed-slider')),
    );
    speedSlider.onChanged!(72);
    await tester.pump();
    expect(
      changedPoint,
      original.copyWith(gpuUpperTemp: 82, fan2Rpm: 3600),
      reason: '72 percent must be written as RPM in the 5000 RPM domain',
    );
  });

  testWidgets('point selector exposes every point and sliders accept arrows', (
    tester,
  ) async {
    FanCurvePoint? changedPoint;
    await _pumpEditor(
      tester,
      width: 800,
      onPointChanged: (_, point) => changedPoint = point,
    );
    await _expandPreciseControls(tester);

    final selector = tester.widget<Wrap>(
      find.byKey(const ValueKey('fan-point-selector')),
    );
    expect(selector.children, hasLength(10));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('fan-point-selector')),
        matching: find.text('10'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('fan-speed-slider')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(changedPoint, isNotNull);
    expect(changedPoint!.fan1Rpm, greaterThan(_curve().points.first.fan1Rpm!));
  });

  testWidgets('drag maps exact plot bounds to temperature and RPM', (
    tester,
  ) async {
    int? changedIndex;
    FanCurvePoint? changedPoint;
    await _pumpEditor(
      tester,
      width: 800,
      onPointChanged: (index, point) {
        changedIndex = index;
        changedPoint = point;
      },
    );

    final plot = find.byKey(const ValueKey('fan-curve-chart-plot'));
    final size = tester.getSize(plot);
    final origin = tester.getTopLeft(plot);
    final gesture = await tester.startGesture(
      origin + Offset(size.width * 0.76, size.height * 0.34),
    );
    await gesture.moveTo(
      origin + Offset(size.width * 0.76, size.height * 0.25),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(changedIndex, 8);
    expect(changedPoint!.cpuUpperTemp, closeTo(76, 1));
    expect(changedPoint!.fan1Rpm, 3650);
    await _expandPreciseControls(tester);
    final selected = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '9'),
    );
    expect(selected.selected, isTrue);
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('fan-speed-slider')))
          .value,
      73,
    );
  });

  testWidgets('edits stay within hysteresis and neighboring curve points', (
    tester,
  ) async {
    FanCurvePoint? changedPoint;
    await _pumpEditor(
      tester,
      width: 800,
      onPointChanged: (_, point) => changedPoint = point,
    );
    await _expandPreciseControls(tester);

    final temperatureSlider = tester.widget<Slider>(
      find.byKey(const ValueKey('fan-temperature-slider')),
    );
    temperatureSlider.onChanged!(0);
    await tester.pump();
    expect(changedPoint!.cpuUpperTemp, _curve().points.first.cpuLowerTemp);

    final speedSlider = tester.widget<Slider>(
      find.byKey(const ValueKey('fan-speed-slider')),
    );
    speedSlider.onChanged!(100);
    await tester.pump();
    expect(changedPoint!.fan1Rpm, _curve().points[1].fan1Rpm);
  });

  testWidgets('tooltip-only dragging leaves the editor controls untouched', (
    tester,
  ) async {
    var edits = 0;
    await _pumpEditor(tester, width: 800, onPointChanged: (_, _) => edits++);
    await _expandPreciseControls(tester);
    final plot = find.byKey(const ValueKey('fan-curve-chart-plot'));
    final origin = tester.getTopLeft(plot);
    final size = tester.getSize(plot);
    final gesture = await tester.startGesture(
      origin + Offset(size.width * 0.2, size.height * 0.9),
    );
    await gesture.moveTo(origin + Offset(-30, size.height + 30));
    await tester.pump();
    final editsAtBoundary = edits;
    expect(editsAtBoundary, greaterThan(0));
    final save = tester.widget(find.byKey(const ValueKey('fan-curve-save')));
    final summary = tester.widget(find.text('Current CPU fan speed'));
    final slider = tester.widget(
      find.byKey(const ValueKey('fan-speed-slider')),
    );

    await gesture.moveTo(origin + Offset(-60, size.height + 60));
    await tester.pump();
    expect(edits, editsAtBoundary);
    expect(
      tester.widget(find.byKey(const ValueKey('fan-curve-save'))),
      same(save),
    );
    expect(tester.widget(find.text('Current CPU fan speed')), same(summary));
    expect(
      tester.widget(find.byKey(const ValueKey('fan-speed-slider'))),
      same(slider),
    );
    await gesture.up();
    await tester.pump();
    expect(
      tester.widget(find.byKey(const ValueKey('fan-curve-save'))),
      same(save),
    );
  });

  testWidgets('subpixel dragging moves the tooltip without another edit', (
    tester,
  ) async {
    var edits = 0;
    await _pumpEditor(tester, width: 800, onPointChanged: (_, _) => edits++);
    final plot = find.byKey(const ValueKey('fan-curve-chart-plot'));
    final origin = tester.getTopLeft(plot);
    final size = tester.getSize(plot);
    final gesture = await tester.startGesture(
      origin + Offset(size.width * 0.2, size.height * 0.9),
    );
    await gesture.moveTo(origin + Offset(size.width * 0.25, size.height * 0.9));
    await tester.pump();
    final editsBeforeMovement = edits;
    final tooltip = find.text('25°  ·  10%');
    final tooltipPosition = tester.getTopLeft(tooltip);
    final save = tester.widget(find.byKey(const ValueKey('fan-curve-save')));

    await gesture.moveBy(const Offset(0.01, 0));
    await tester.pump();
    expect(edits, editsBeforeMovement);
    expect(tester.getTopLeft(tooltip).dx, greaterThan(tooltipPosition.dx));
    expect(
      tester.widget(find.byKey(const ValueKey('fan-curve-save'))),
      same(save),
    );

    await gesture.moveBy(Offset(0, -size.height * 0.01));
    await tester.pump();
    expect(edits, editsBeforeMovement + 1);
    expect(find.text('25°  ·  11%'), findsOneWidget);
    await gesture.cancel();
    await tester.pump();
    expect(find.text('25°  ·  11%'), findsNothing);
  });

  testWidgets('applying a curve clears an active drag and prevents edits', (
    tester,
  ) async {
    var edits = 0;
    await _pumpEditor(tester, width: 800, onPointChanged: (_, _) => edits++);
    final plot = find.byKey(const ValueKey('fan-curve-chart-plot'));
    final origin = tester.getTopLeft(plot);
    final size = tester.getSize(plot);
    final gesture = await tester.startGesture(
      origin + Offset(size.width * 0.2, size.height * 0.9),
    );
    await gesture.moveTo(origin + Offset(size.width * 0.25, size.height * 0.9));
    await tester.pump();
    expect(find.text('25°  ·  10%'), findsOneWidget);
    final editsBeforeApplying = edits;

    await _pumpEditor(
      tester,
      width: 800,
      isApplying: true,
      onPointChanged: (_, _) => edits++,
    );
    expect(find.text('25°  ·  10%'), findsNothing);
    await gesture.moveBy(const Offset(0, -30));
    await gesture.up();
    await tester.pump();
    expect(edits, editsBeforeApplying);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save is enabled only while dirty and not applying', (
    tester,
  ) async {
    var saves = 0;
    await _pumpEditor(tester, width: 800, onSave: () => saves++);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('fan-curve-save')))
          .onPressed,
      isNull,
    );

    await _pumpEditor(tester, width: 800, dirty: true, onSave: () => saves++);
    expect(find.textContaining('Unsaved changes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fan-curve-save')));
    expect(saves, 1);

    await _pumpEditor(
      tester,
      width: 800,
      dirty: true,
      isApplying: true,
      onSave: () => saves++,
    );
    await _expandPreciseControls(tester);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('fan-curve-save')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('fan-temperature-slider')))
          .onChanged,
      isNull,
    );
  });
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required double width,
  bool dirty = false,
  bool isApplying = false,
  FanChannel channel = FanChannel.cpu,
  void Function(int index, FanCurvePoint point)? onPointChanged,
  VoidCallback? onSave,
}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    YaruTheme(
      data: const YaruThemeData(),
      builder: (context, yaru, child) => MaterialApp(
        theme: yaru.theme,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _EditorHarness(
              curve: _curve(),
              dirty: dirty,
              isApplying: isApplying,
              channel: channel,
              onPointChanged: onPointChanged,
              onSave: onSave,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _EditorHarness extends StatefulWidget {
  const _EditorHarness({
    required this.curve,
    required this.dirty,
    required this.isApplying,
    required this.channel,
    this.onPointChanged,
    this.onSave,
  });

  final FanCurve curve;
  final bool dirty;
  final bool isApplying;
  final FanChannel channel;
  final void Function(int index, FanCurvePoint point)? onPointChanged;
  final VoidCallback? onSave;

  @override
  State<_EditorHarness> createState() => _EditorHarnessState();
}

class _EditorHarnessState extends State<_EditorHarness> {
  late FanCurve _curve = widget.curve;

  @override
  Widget build(BuildContext context) {
    return FanCurveEditor(
      curve: _curve,
      channel: widget.channel,
      currentTemperature: widget.channel == FanChannel.cpu ? 64 : 58,
      currentRpm: widget.channel == FanChannel.cpu ? 2180 : 1940,
      accent: const Color(0xFF8056D6),
      enabled: true,
      dirty: widget.dirty,
      isApplying: widget.isApplying,
      onPointChanged: (index, point) {
        setState(() => _curve = _curve.copyWithPoint(index, point));
        widget.onPointChanged?.call(index, point);
      },
      onSave: widget.onSave,
    );
  }
}

Future<void> _expandPreciseControls(WidgetTester tester) async {
  await tester.tap(find.text('Precise point controls'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
