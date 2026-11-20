import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/package_power_telemetry_service.dart';
import 'package:legion_frontend/core/services/control_launcher.dart';

void main() {
  test('sensor polling before approval leaves the helper stopped', () async {
    var launches = 0;
    final client = SessionPackagePowerClient(
      launcher: ControlLauncher(
        executable: '/fixture/helper',
        session: HelperSession.packagePower,
        startProcess:
            (
              _,
              _, {
              required environment,
              required workingDirectory,
              required includeParentEnvironment,
            }) {
              launches++;
              throw StateError('Unexpected launch');
            },
      ),
    );
    expect(await client.readPackagePowerWatts(), isNull);
    expect(launches, 0);
    await client.close();
  });
}
