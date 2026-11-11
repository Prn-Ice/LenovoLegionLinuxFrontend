import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/services/native_portable_control_transport.dart';

void main() {
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
