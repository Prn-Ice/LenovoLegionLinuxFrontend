import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/services/native_portable_control_transport.dart';

void main() {
  testWidgets('native CLI discovery rejects caller-selected paths', (_) async {
    await expectLater(
      const MethodChannel(
        'io.github.prnice.legion/portable_control',
      ).invokeMethod<Object>('findHostCli', {
        'path': '/tmp/caller-controlled-cli',
      }),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'invalid-arguments',
        ),
      ),
    );
  });
  testWidgets(
    'native portable channel rejects invalid endpoints before connecting',
    (_) async {
      final client = LegionControlClient(
        transport: NativePortableControlTransport(
          endpoint: const PortableControlEndpoint(
            address: 'tcp:host=localhost,port=123',
            unit:
                'legion-bootstrap-probe-01234567-89ab-4cde-8fab-0123456789ab.service',
            helperPid: 123,
            busName: ':1.23',
          ),
        ),
      );
      try {
        await expectLater(
          client.setToggle(ControlToggle.batteryConservation, true),
          throwsA(isA<LegionControlNotSupportedException>()),
        );
      } finally {
        await client.close();
      }
    },
  );
}
