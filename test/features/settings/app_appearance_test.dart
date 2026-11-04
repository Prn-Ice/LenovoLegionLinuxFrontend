import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/app/app.dart';
import 'package:legion_frontend/core/theme/legion_accent.dart';
import 'package:legion_frontend/features/dashboard/bloc/dashboard_bloc.dart';
import 'package:legion_frontend/features/dashboard/bloc/dashboard_event.dart';
import 'package:legion_frontend/features/dashboard/bloc/dashboard_state.dart';
import 'package:legion_frontend/features/dashboard/providers/dashboard_provider.dart';
import 'package:legion_frontend/features/dashboard/models/system_status.dart';
import 'package:legion_frontend/features/settings/bloc/settings_bloc.dart';
import 'package:legion_frontend/features/settings/bloc/settings_event.dart';
import 'package:legion_frontend/features/settings/bloc/settings_state.dart';
import 'package:legion_frontend/features/settings/providers/settings_provider.dart';
import 'package:yaru/yaru.dart';

class _Dashboard extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

class _Settings extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

void main() {
  testWidgets(
    'real app themes track observed dashboard modes and preserve manual fallback',
    (tester) async {
      final dashboard = _Dashboard();
      final settings = _Settings();
      final modes = StreamController<DashboardState>();
      final preferences = StreamController<SettingsState>();
      final manual = SettingsState.initial().copyWith(
        yaruVariant: YaruVariant.blue,
      );
      final follow = manual.copyWith(accentFollowsPowerMode: true);
      DashboardState observed(String profile) {
        final state = DashboardState.initial();
        return state.copyWith(
          snapshot: state.snapshot.copyWith(
            status: SystemStatus(
              updatedAt: DateTime.utc(2026),
              powerProfile: profile,
            ),
          ),
        );
      }

      whenListen(dashboard, modes.stream, initialState: observed('quiet'));
      whenListen(settings, preferences.stream, initialState: follow);
      final container = ProviderContainer(
        overrides: [
          dashboardBlocProvider.overrideWith((ref) => dashboard),
          settingsBlocProvider.overrideWith((ref) => settings),
        ],
      );
      // The real navigation shell keeps the observed dashboard alive even when
      // appearance following is disabled.
      final shellObservation = container.listen(
        dashboardBlocProvider,
        (_, _) {},
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          // Isolate the real app/theme boundary from unrelated shell hardware I/O.
          child: const LegionFrontendApp(home: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();
      void expectAccent(Color color) {
        final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        for (final theme in [app.theme!, app.darkTheme!]) {
          expect(theme.colorScheme.primary, color);
          expect(
            theme.textSelectionTheme.selectionColor,
            color.withValues(alpha: 0.4),
          );
        }
      }

      expectAccent(LegionAccent.quiet.color);
      modes.add(observed('performance'));
      await tester.pumpAndSettle();
      expectAccent(LegionAccent.performance.color);
      modes.add(observed('unavailable'));
      await tester.pumpAndSettle();
      expectAccent(YaruVariant.blue.color);
      preferences.add(manual);
      await tester.pumpAndSettle();
      modes.add(observed('balanced'));
      await tester.pumpAndSettle();
      expectAccent(YaruVariant.blue.color);
      preferences.add(follow);
      await tester.pumpAndSettle();
      expectAccent(LegionAccent.balanced.color);
      await tester.pumpWidget(const SizedBox());
      shellObservation.close();
      container.dispose();
      await preferences.close();
      await modes.close();
      await tester.pump();
    },
  );
}
