import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/fans/models/fan_curve.dart';
import 'package:legion_frontend/features/fans/view/fan_curve_editor.dart';
import 'package:yaru/yaru.dart';

FanCurve _curve() => FanCurve(
  name: 'widget-test',
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
    expect(find.text('Current CPU fan'), findsOneWidget);
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
    expect(changedPoint!.fan1Rpm, greaterThan(_curve().points.first.fan1Rpm));
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
