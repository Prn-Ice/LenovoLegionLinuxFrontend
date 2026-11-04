import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/core/providers/system_services_provider.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:riverbloc/riverbloc.dart';

void main() {
  test(
    'disposing the production provider closes its lazy control connection',
    () async {
      final container = ProviderContainer();
      final client = container.read(legionControlClientProvider);
      container.dispose();
      await expectLater(
        client.setToggle(ControlToggle.hybridMode, true),
        throwsA(isA<LegionControlUnavailableException>()),
      );
    },
  );

  test('recreating the production provider closes the old client', () async {
    final container = ProviderContainer.test();
    final previous = container.read(legionControlClientProvider);
    container.invalidate(legionControlClientProvider);
    await container.pump();
    final current = container.read(legionControlClientProvider);
    expect(current, isNot(same(previous)));
    await expectLater(
      previous.getCapabilities(),
      throwsA(isA<LegionControlUnavailableException>()),
    );
  });
}
