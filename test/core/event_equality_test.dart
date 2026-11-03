import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/about/bloc/about_event.dart';
import 'package:legion_frontend/features/dashboard/bloc/dashboard_event.dart';
import 'package:legion_frontend/features/settings/bloc/settings_event.dart';

void main() {
  test('different commands remain distinct even without payloads', () {
    expect(const AboutStarted(), isNot(const AboutRefreshRequested()));
    expect(const DashboardStarted(), isNot(const DashboardRefreshRequested()));
    expect(const DashboardStarted(), isNot(const DashboardTicked()));
    expect(const SettingsStarted(), isNot(const SettingsRefreshRequested()));
    expect({const AboutStarted(), const AboutRefreshRequested()}, hasLength(2));
  });

  test('the same command and payload remain equal', () {
    expect(const SettingsStarted(), const SettingsStarted());
    expect(
      const SettingsServiceToggled(serviceId: 'legiond_stack', enabled: true),
      const SettingsServiceToggled(serviceId: 'legiond_stack', enabled: true),
    );
    expect(
      const SettingsServiceToggled(serviceId: 'legiond_stack', enabled: true),
      isNot(
        const SettingsServiceToggled(
          serviceId: 'legiond_stack',
          enabled: false,
        ),
      ),
    );
  });
}
