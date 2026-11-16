import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/about/bloc/about_event.dart';
import 'package:legion_frontend/features/dashboard/bloc/dashboard_event.dart';
import 'package:legion_frontend/features/settings/bloc/settings_event.dart';

void main() {
  test('different commands remain distinct even without payloads', () {
    expect(const AboutStarted(), isNot(const AboutRefreshRequested()));
    expect(const DashboardStarted(), isNot(const DashboardRefreshRequested()));
    expect(const DashboardStarted(), isNot(const DashboardTicked()));
    expect(
      const AccentFollowsPowerModeChanged(true),
      isNot(const AccentFollowsPowerModeChanged(false)),
    );
    expect({const AboutStarted(), const AboutRefreshRequested()}, hasLength(2));
  });

  test('the same command and payload remain equal', () {
    expect(
      const AccentFollowsPowerModeChanged(true),
      const AccentFollowsPowerModeChanged(true),
    );
    expect(
      const AccentFollowsPowerModeChanged(true),
      isNot(const AccentFollowsPowerModeChanged(false)),
    );
  });
}
