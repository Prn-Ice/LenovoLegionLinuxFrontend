import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/dashboard/widgets/sensor_strip.dart';
import 'package:legion_frontend/features/sensors/models/live_sensor_snapshot.dart';

LiveSensorSnapshot _snapshot({
  double? cpuTempC,
  double? gpuTempC,
  double? cpuUtilPercent,
}) => LiveSensorSnapshot(
  cpuName: 'CPU',
  cpuTempC: cpuTempC,
  cpuUtilPercent: cpuUtilPercent,
  cpuClockGhz: null,
  cpuPackagePowerW: null,
  fan1Rpm: null,
  fan2Rpm: null,
  gpuName: null,
  gpuTempC: gpuTempC,
  gpuUtilPercent: null,
  gpuClockGhz: null,
  gpuVramUsedGb: null,
  gpuVramTotalGb: null,
  gpuFanRpm: null,
  gpuPowerDrawW: null,
  gpuIsDiscrete: true,
  motherboardTempC: null,
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

  testWidgets('renders gauges and a load tile from the snapshot', (
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
    expect(find.text('CPU load'), findsOneWidget); // utilisation tile
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
}
