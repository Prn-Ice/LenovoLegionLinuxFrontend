import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/gpu_reading.dart';
import 'package:legion_frontend/features/dashboard/models/dashboard_metric.dart';
import 'package:legion_frontend/features/dashboard/widgets/sensor_strip.dart';
import 'package:legion_frontend/features/sensors/models/live_sensor_snapshot.dart';

LiveSensorSnapshot _snapshot({
  double? cpuTempC,
  double? gpuTempC,
  GpuReading? igpu,
  double? dgpuUsage,
  double? cpuUtilPercent,
  int? fan2Rpm,
  double? cpuPackagePowerW,
  double? gpuPowerDrawW,
  double? motherboardTempC,
}) => LiveSensorSnapshot(
  cpuName: 'CPU',
  cpuTempC: cpuTempC,
  cpuUtilPercent: cpuUtilPercent,
  cpuClockGhz: null,
  cpuPackagePowerW: cpuPackagePowerW,
  fan1Rpm: null,
  fan2Rpm: fan2Rpm,
  fan2MaxRpm: 10000,
  igpu: igpu,
  dgpu: GpuReading(
    tempC: gpuTempC,
    usagePercent: dgpuUsage,
    powerDrawW: gpuPowerDrawW,
  ),
  motherboardTempC: motherboardTempC,
  batteryPercent: null,
  batteryCharging: null,
  batteryPowerDrawW: null,
  diskTempC: null,
);

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  const accent = Color(0xFF3A9D4F);

  testWidgets('renders temperatures and CPU usage from the snapshot', (
    tester,
  ) async {
    await _pump(
      tester,
      SensorStrip(
        snapshot: _snapshot(cpuTempC: 72, gpuTempC: 61, cpuUtilPercent: 40),
        accent: accent,
      ),
    );

    expect(find.text('CPU temp'), findsOneWidget); // gauge label
    expect(find.text('dGPU temp'), findsOneWidget); // discrete gpu gauge label
    expect(find.textContaining('72'), findsWidgets);
    expect(find.text('CPU usage'), findsOneWidget);
  });

  testWidgets('keeps power in the mode hero and system temperature secondary', (
    tester,
  ) async {
    await _pump(
      tester,
      SensorStrip(
        snapshot: _snapshot(
          fan2Rpm: 2200,
          cpuUtilPercent: 40,
          cpuPackagePowerW: 8.8,
          gpuPowerDrawW: 2.3,
          motherboardTempC: 48.2,
        ),
        accent: accent,
      ),
    );

    expect(find.text('GPU fan (RPM)'), findsOneWidget);
    expect(find.textContaining('2200'), findsWidgets);
    expect(find.text('CPU package power'), findsNothing);
    expect(find.text('GPU power'), findsNothing);
    expect(find.text('System 48.2°C'), findsOneWidget);
    expect(find.text('Board temp'), findsNothing);
  });

  testWidgets('shows the unavailable message when no sensors are present', (
    tester,
  ) async {
    await _pump(
      tester,
      SensorStrip(snapshot: LiveSensorSnapshot.initial(), accent: accent),
    );

    expect(find.text('Sensor data unavailable.'), findsOneWidget);
  });

  testWidgets('shows both GPUs independently, including genuine zero usage', (
    tester,
  ) async {
    await _pump(
      tester,
      SensorStrip(
        snapshot: _snapshot(
          cpuUtilPercent: 15,
          igpu: const GpuReading(usagePercent: 0, tempC: 42),
          dgpuUsage: 73,
          gpuTempC: 68,
        ),
        accent: accent,
      ),
    );
    expect(find.text('CPU usage'), findsOneWidget);
    expect(find.text('iGPU usage'), findsOneWidget);
    expect(find.text('dGPU usage'), findsOneWidget);
    expect(find.text('iGPU temp'), findsOneWidget);
    expect(find.text('dGPU temp'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets(
    'hides missing usage and respects individual visibility choices',
    (tester) async {
      await _pump(
        tester,
        SensorStrip(
          snapshot: _snapshot(
            cpuUtilPercent: 15,
            igpu: const GpuReading(tempC: 42),
            dgpuUsage: 73,
          ),
          hiddenMetrics: const {
            DashboardMetric.cpuUsage,
            DashboardMetric.dgpuUsage,
          },
          accent: accent,
        ),
      );
      expect(find.text('CPU usage'), findsNothing);
      expect(find.text('iGPU usage'), findsNothing);
      expect(find.text('dGPU usage'), findsNothing);
      expect(find.text('iGPU temp'), findsOneWidget);
    },
  );

  testWidgets('shows a recovery hint when all readings are hidden', (
    tester,
  ) async {
    await _pump(
      tester,
      SensorStrip(
        snapshot: _snapshot(cpuUtilPercent: 15),
        hiddenMetrics: DashboardMetric.values.toSet(),
        accent: accent,
      ),
    );
    expect(
      find.text('No readings to show. Choose readings in Settings.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'keeps separate readings readable in a narrow window with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(420, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(
        tester,
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: SensorStrip(
            snapshot: _snapshot(
              cpuUtilPercent: 15,
              igpu: const GpuReading(usagePercent: 21),
              dgpuUsage: 73,
            ),
            accent: accent,
          ),
        ),
      );
      expect(find.text('iGPU usage'), findsOneWidget);
      expect(find.text('dGPU usage'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
