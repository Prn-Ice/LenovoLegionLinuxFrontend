import 'package:flutter_test/flutter_test.dart';
import 'package:dbus/dbus.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/features/settings/models/service_control.dart';
import 'package:legion_frontend/features/settings/repository/settings_repository.dart';

class _Transport implements LegionControlTransport {
  Object? failure;
  String? method;
  List<Object>? arguments;

  @override
  Future<void> authorize() async {}

  @override
  Future<void> call(String method, List<Object> arguments) async {
    if (failure != null) throw failure!;
    this.method = method;
    this.arguments = arguments;
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('service changes use SetServiceEnabled on the control client', () async {
    final transport = _Transport();
    final repository = SettingsRepository(
      controlClient: LegionControlClient(transport: transport),
    );
    const service = ServiceControl(
      id: 'legiond_stack',
      label: 'legiond services',
      units: ['legiond.service'],
      supported: true,
      active: false,
      enabled: false,
    );

    await repository.setServiceEnabled(service, true);

    expect(transport.method, 'SetServiceEnabled');
    expect(transport.arguments, ['legiond_stack', true]);
  });

  test('D-Bus authorization errors are wrapped by the repository', () async {
    final transport = _Transport()
      ..failure = DBusAccessDeniedException(
        DBusMethodErrorResponse.accessDenied(),
      );
    final repository = SettingsRepository(
      controlClient: LegionControlClient(transport: transport),
    );
    const service = ServiceControl(
      id: 'legiond_stack',
      label: 'legiond services',
      units: ['legiond.service'],
      supported: true,
      active: false,
      enabled: false,
    );

    await expectLater(
      repository.setServiceEnabled(service, true),
      throwsA(
        isA<SettingsRepositoryException>().having(
          (error) => error.message,
          'message',
          contains('AccessDenied'),
        ),
      ),
    );
  });
}
