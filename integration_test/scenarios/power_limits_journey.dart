import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:legion_frontend/core/widgets/app_shell_components.dart';
import 'package:legion_frontend/features/power/bloc/power_bloc.dart';
import 'package:legion_frontend/features/power/bloc/power_event.dart';
import 'package:legion_frontend/features/power/providers/power_provider.dart';
import 'package:legion_frontend/features/power/view/power_page.dart';

import '../support/journey.dart';
import '../support/safe_app.dart';

enum _LimitAvailability { nonCustom, battery, unknownAc, unsupported }

void main() {
  testWidgets('power limits stay staged until grouped Apply and readback', (
    tester,
  ) async {
    final app = await _launch(tester);
    final values = await _stagePair(tester);
    await _expectInitialHardware(app);
    _expectNoWrites(app);

    await _tap(tester, find.text('Revert'));
    expect(find.text('Unsaved limit changes'), findsNothing);
    _expectCurrent(tester, FixturePowerLimit.sustained, 45);
    _expectCurrent(tester, FixturePowerLimit.boost, 80);
    _expectNoWrites(app);

    expect(await _stagePair(tester), values);
    await _tap(tester, find.text('Apply changes'));
    await _waitForApplied(tester);
    expect(app.powerLimitRequests, values);
    expect(app.powerLimitWrites, values);
    expect(app.authorizations, 1);
    await _expectReadback(tester, app, values);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed grouped power limits roll back and retain retryable edits',
    (tester) async {
      final app = await _launch(tester);
      final values = await _stagePair(tester);
      app.failNextPowerLimit = FixturePowerLimit.boost;
      await _tap(tester, find.text('Apply changes'));
      await waitFor(
        tester,
        () => find.byType(AppErrorDialog).evaluate().isNotEmpty,
        description: 'power-limit failure dialog after rollback',
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Test backend rejected the power limit'),
        findsOneWidget,
      );
      expect(app.powerLimitRequests, [
        ...values,
        (FixturePowerLimit.sustained, 45),
      ]);
      expect(app.powerLimitWrites, [
        values.first,
        (FixturePowerLimit.sustained, 45),
      ]);
      await _expectInitialHardware(app);
      final state = _container(tester).read(powerBlocProvider);
      expect(state.isApplying, isFalse);
      expect(state.noticeMessage, isNull);
      for (final limit in FixturePowerLimit.values) {
        expect(
          state.powerLimits
              .singleWhere((r) => r.spec.feature == limit.feature)
              .value,
          limit.initialValue,
        );
      }

      await _tap(tester, find.text('Close'));
      expect(find.text('Unsaved limit changes'), findsOneWidget);
      for (final (limit, value) in values) {
        _expectCurrent(tester, limit, limit.initialValue);
        expect(tester.widget<Slider>(_slider(limit)).value.round(), value);
      }
      await _tap(tester, find.text('Apply changes'));
      await _waitForApplied(tester);
      expect(app.powerLimitRequests, [
        ...values,
        (FixturePowerLimit.sustained, 45),
        ...values,
      ]);
      expect(app.powerLimitWrites, [
        values.first,
        (FixturePowerLimit.sustained, 45),
        ...values,
      ]);
      await _expectReadback(tester, app, values);
      expect(tester.takeException(), isNull);
    },
  );

  for (final availability in _LimitAvailability.values) {
    final condition = switch (availability) {
      _LimitAvailability.nonCustom => 'outside Custom mode',
      _LimitAvailability.battery => 'on battery power',
      _LimitAvailability.unknownAc => 'with unknown AC status',
      _LimitAvailability.unsupported => 'without supported limits',
    };
    testWidgets('power limits make no writes $condition', (tester) async {
      final app = await _launch(tester, availability: availability);
      final guidance = switch (availability) {
        _LimitAvailability.nonCustom =>
          'Switch to Custom mode to edit controller power limits.',
        _LimitAvailability.battery =>
          'Connect AC power to edit custom power limits.',
        _LimitAvailability.unknownAc =>
          'AC power status is unavailable, so limit changes are disabled.',
        _LimitAvailability.unsupported =>
          'The platform controller did not provide usable power-limit values.',
      };
      await tester.ensureVisible(find.text(guidance));
      await tester.pumpAndSettle();
      expect(find.text(guidance), findsOneWidget);
      if (availability == _LimitAvailability.unsupported) {
        expect(find.byType(Slider), findsNothing);
      } else {
        for (final limit in FixturePowerLimit.values) {
          final slider = _slider(limit);
          expect(tester.widget<Slider>(slider).onChanged, isNull);
          await tester.ensureVisible(slider);
          await tester.pumpAndSettle();
          await tester.tap(slider);
          await tester.pumpAndSettle();
          _expectCurrent(tester, limit, limit.initialValue);
        }
        await _expectInitialHardware(app);
      }
      expect(find.text('Apply changes'), findsNothing);
      _expectNoWrites(app);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<SafeApp> _launch(
  WidgetTester tester, {
  _LimitAvailability? availability,
}) async {
  final app = await SafeApp.create(
    acOnline: availability != _LimitAvailability.battery,
    includePowerLimitFixture: availability != _LimitAvailability.unsupported,
    profileChoices: const [
      FixturePlatformProfile.balanced,
      FixturePlatformProfile.custom,
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await app.dispose();
  });
  if (availability != _LimitAvailability.nonCustom) {
    await File('${app.directory.path}/sys/firmware/acpi/platform_profile')
        .writeAsString('custom\n');
  }
  if (availability == _LimitAvailability.unknownAc) {
    await File('${app.directory.path}/sys/class/power_supply/AC/online')
        .delete();
  }
  await app.launch(
    additionalOverrides: [
      // A periodic read must not repair a missing write readback.
      powerBlocProvider.overrideWith(
        (ref) => PowerBloc(
          repository: ref.watch(powerRepositoryProvider),
          pollInterval: const Duration(days: 1),
        )..add(const PowerStarted()),
      ),
    ],
  );
  await waitFor(
    tester,
    () => find.text('Power').hitTestable().evaluate().isNotEmpty,
    description: 'Power navigation',
  );
  await tester.tap(find.text('Power').hitTestable().first);
  await waitFor(
    tester,
    () => find.byKey(const ValueKey('power-limits-card')).evaluate().isNotEmpty,
    description: 'loaded Power limits card',
  );
  await tester.pumpAndSettle();
  return app;
}

Future<List<(FixturePowerLimit, int)>> _stagePair(WidgetTester tester) async {
  final values = <(FixturePowerLimit, int)>[];
  for (final limit in [FixturePowerLimit.sustained, FixturePowerLimit.boost]) {
    final slider = _slider(limit);
    expect(tester.widget<Slider>(slider).onChanged, isNotNull);
    await _tap(tester, slider);
    final value = tester.widget<Slider>(slider).value.round();
    expect(value, isNot(limit.initialValue));
    values.add((limit, value));
  }
  expect(find.text('Unsaved limit changes'), findsOneWidget);
  return values;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(PowerPage)));

Future<void> _waitForApplied(WidgetTester tester) => waitFor(
  tester,
  () =>
      !_container(tester).read(powerBlocProvider).isApplying &&
      find.text('Unsaved limit changes').evaluate().isEmpty,
  description: 'grouped power-limit completion and confirmed readback',
);

void _expectNoWrites(SafeApp app) {
  expect(app.authorizations, 0);
  expect(app.powerLimitRequests, isEmpty);
  expect(app.powerLimitWrites, isEmpty);
  expect(app.platformProfileRequests, isEmpty);
  expect(app.requests, isEmpty);
}

Future<void> _expectInitialHardware(SafeApp app) async {
  for (final limit in FixturePowerLimit.values) {
    expect(await _file(app, limit).readAsString(), '${limit.initialValue}\n');
  }
}

Future<void> _expectReadback(
  WidgetTester tester,
  SafeApp app,
  List<(FixturePowerLimit, int)> values,
) async {
  final state = _container(tester).read(powerBlocProvider);
  expect(state.errorMessage, isNull);
  for (final (limit, value) in values) {
    expect(await _file(app, limit).readAsString(), '$value\n');
    expect(
      state.powerLimits
          .singleWhere((r) => r.spec.feature == limit.feature)
          .value,
      value,
    );
    _expectCurrent(tester, limit, value);
  }
  expect(
    await _file(app, FixturePowerLimit.gpu).readAsString(),
    '${FixturePowerLimit.gpu.initialValue}\n',
  );
  expect(find.text('Unsaved limit changes'), findsNothing);
  expect(app.platformProfileRequests, isEmpty);
  expect(app.requests, isEmpty);
}

File _file(SafeApp app, FixturePowerLimit limit) => File(
  '${app.directory.path}/sys/module/legion_laptop/drivers/'
  'platform:legion/legion/${limit.attribute}',
);

String _id(FixturePowerLimit limit) => switch (limit) {
  FixturePowerLimit.sustained => 'cpu_longterm',
  FixturePowerLimit.boost => 'cpu_shortterm',
  FixturePowerLimit.gpu => 'gpu_ctgp',
};

Finder _slider(FixturePowerLimit limit) =>
    find.byKey(ValueKey('power-limit-slider-${_id(limit)}'));

void _expectCurrent(WidgetTester tester, FixturePowerLimit limit, int value) {
  expect(
    tester
        .widget<Text>(find.byKey(ValueKey('power-limit-current-${_id(limit)}')))
        .data,
    '$value W',
  );
}
