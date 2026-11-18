import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:legion_frontend/core/models/app_failure.dart';
import 'package:legion_frontend/core/widgets/app_shell_components.dart';
import 'package:legion_frontend/features/fans/bloc/fans_bloc.dart';
import 'package:legion_frontend/features/fans/bloc/fans_event.dart';
import 'package:legion_frontend/features/fans/bloc/fans_state.dart';
import 'package:legion_frontend/features/fans/models/fan_curve.dart';
import 'package:legion_frontend/features/fans/providers/fans_provider.dart';
import 'package:legion_frontend/features/fans/view/fan_curve_editor.dart';
import 'package:legion_frontend/features/fans/view/fans_page.dart';

import '../support/journey.dart';
import '../support/safe_app.dart';

enum _SaveFailure { rejected, unchanged }

final _save = find.byKey(const ValueKey('fan-curve-save'));

void main() {
  testWidgets('fan curve edits stay local until confirmed save and readback', (
    tester,
  ) async {
    final app = await _launch(tester);
    final before = await _files(app);
    final original = _state(tester).authoritativeFanCurve!;
    final expected = await _edit(tester, original);
    expect(await _files(app), before);
    expect(app.authorizations, 0);
    expect(app.fanCurveRequests, isEmpty);

    await _openConfirmation(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(app.authorizations, 0);
    expect(app.fanCurveRequests, isEmpty);
    expect(await _files(app), before);
    expect(_state(tester).fanCurve, expected);
    expect(_state(tester).fanCurveDirty, isTrue);

    await _apply(tester);
    await _waitForReadback(tester);
    expect(app.authorizations, 1);
    expect(app.fanCurveRequests, hasLength(1));
    expect(app.fanCurveCompletions, app.fanCurveRequests);
    await _expectApplied(tester, app, expected, before);
  });

  for (final failure in _SaveFailure.values) {
    final description = failure == _SaveFailure.rejected
        ? 'a rejected write'
        : 'unchanged hardware readback';
    testWidgets(
      'fan curve preserves its draft after $description and retries',
      (tester) async {
        final app = await _launch(tester);
        final before = await _files(app);
        final original = _state(tester).authoritativeFanCurve!;
        final expected = await _edit(tester, original);
        if (failure == _SaveFailure.rejected) {
          app.nextFailure = ControlFailure.commandFailed;
        } else {
          app.fanCurveResult = FixtureFanCurveResult.unchanged;
        }
        await _apply(tester);
        await waitFor(
          tester,
          () => find.byType(AppErrorDialog).evaluate().isNotEmpty,
          description: 'fan-curve save failure dialog',
        );
        await tester.pumpAndSettle();
        if (failure == _SaveFailure.rejected) {
          final dialog = tester.widget<AppErrorDialog>(
            find.byType(AppErrorDialog),
          );
          expect(
            AppFailure.from(dialog.message).kind,
            AppFailureKind.commandFailed,
          );
          expect(
            find.textContaining('Test backend rejected the fan curve'),
            findsOneWidget,
          );
        } else {
          expect(
            find.textContaining(
              'The reported fan curve does not match your changes.',
            ),
            findsOneWidget,
          );
        }
        expect(await _files(app), before);
        expect(app.fanCurveRequests, hasLength(1));
        expect(
          app.fanCurveCompletions,
          hasLength(failure == _SaveFailure.rejected ? 0 : 1),
        );
        expect(_state(tester).isApplying, isFalse);
        expect(_state(tester).noticeMessage, isNull);
        expect(_state(tester).authoritativeFanCurve, original);
        expect(_state(tester).fanCurve, expected);
        expect(_state(tester).fanCurveDirty, isTrue);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        app.fanCurveResult = FixtureFanCurveResult.applied;
        await _apply(tester);
        await _waitForReadback(tester);
        expect(app.fanCurveRequests, hasLength(2));
        expect(app.fanCurveRequests.first, app.fanCurveRequests.last);
        await _expectApplied(tester, app, expected, before);
      },
    );
  }

  testWidgets('unavailable fan table exposes no curve save or write', (
    tester,
  ) async {
    final app = await _launch(tester, supported: false);
    expect(find.text('Fan curve editing unavailable'), findsOneWidget);
    expect(_save, findsNothing);
    expect(_state(tester).fanCurve, isNull);
    expect(app.authorizations, 0);
    expect(app.fanCurveRequests, isEmpty);
    expect(app.fanCurveCompletions, isEmpty);
    _expectNoOtherWrites(app);
    expect(tester.takeException(), isNull);
  });
}

Future<SafeApp> _launch(WidgetTester tester, {bool supported = true}) async {
  final app = await SafeApp.create(includeFanFixture: supported);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await app.dispose();
  });
  await app.launch(
    additionalOverrides: [
      // Require the save's readback; polling must not repair stale state.
      fansBlocProvider.overrideWith(
        (ref) => FansBloc(
          repository: ref.watch(fansRepositoryProvider),
          pollInterval: const Duration(days: 1),
        )..add(const FansStarted()),
      ),
    ],
  );
  await waitFor(
    tester,
    () => find.text('Fans').hitTestable().evaluate().isNotEmpty,
    description: 'Fans navigation',
  );
  await tester.tap(find.text('Fans').hitTestable().first);
  await tester.pumpAndSettle();
  await waitFor(
    tester,
    () =>
        find.byType(FansPage).evaluate().length == 1 &&
        _state(tester).hasLoaded,
    description: 'loaded Fans page',
  );
  await tester.pumpAndSettle();
  return app;
}

Future<FanCurve> _edit(WidgetTester tester, FanCurve original) async {
  await _tap(tester, find.text('Precise point controls'));
  for (final channel in FanChannel.values) {
    await _tap(tester, find.text(channel.label));
    await _tap(tester, find.byKey(const ValueKey('fan-temperature-slider')));
    await _tap(tester, find.byKey(const ValueKey('fan-speed-slider')));
  }
  // Tapping the slider midpoints exceeds the next point. Edits must clamp to
  // that neighbour, leaving every other field and point unchanged.
  final expected = original.copyWithPoint(
    0,
    original.points.first.copyWith(
      cpuUpperTemp: 40,
      gpuUpperTemp: 42,
      fan1Rpm: 1569,
      fan2Rpm: 1412,
    ),
  );
  expect(_state(tester).fanCurve, expected);
  expect(_state(tester).authoritativeFanCurve, original);
  expect(_state(tester).fanCurveDirty, isTrue);
  expect(find.text('42°C'), findsOneWidget);
  expect(find.text('16%  ·  1412 RPM'), findsOneWidget);
  return expected;
}

Future<void> _openConfirmation(WidgetTester tester) async {
  await _tap(tester, _save);
  expect(find.text('Apply fan curve'), findsOneWidget);
}

Future<void> _apply(WidgetTester tester) async {
  await _openConfirmation(tester);
  await tester.tap(find.text('Apply curve'));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

FansState _state(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(FansPage)))
        .read(fansBlocProvider);

Future<void> _waitForReadback(WidgetTester tester) => waitFor(
  tester,
  () => !_state(tester).isApplying && !_state(tester).fanCurveDirty,
  description: 'confirmed fan-curve save and readback',
);

Future<Map<String, String>> _files(SafeApp app) async {
  final directory = Directory(
    '${app.directory.path}/sys/module/legion_laptop/drivers/'
    'platform:legion/legion/hwmon/hwmon0',
  );
  final files = await directory.list().toList();
  return {
    for (final file in files)
      if (file is File) file.uri.pathSegments.last: await file.readAsString(),
  };
}

Future<void> _expectApplied(
  WidgetTester tester,
  SafeApp app,
  FanCurve expected,
  Map<String, String> before,
) async {
  expect(await _files(app), {
    ...before,
    'pwm1_auto_point1_pwm': '40\n',
    'pwm2_auto_point1_pwm': '40\n',
    'pwm1_auto_point1_temp': '40\n',
    'pwm2_auto_point1_temp': '42\n',
  });
  expect(_state(tester).authoritativeFanCurve, expected);
  expect(_state(tester).fanCurve, expected);
  expect(_state(tester).errorMessage, isNull);
  await tester.pumpAndSettle();
  expect(find.text('42°C'), findsOneWidget);
  expect(find.text('16%  ·  1412 RPM'), findsOneWidget);
  await _tap(tester, find.text(FanChannel.cpu.label));
  expect(find.text('40°C'), findsOneWidget);
  expect(find.text('16%  ·  1569 RPM'), findsOneWidget);
  expect(find.text('No unsaved curve changes.'), findsOneWidget);
  expect(tester.widget<FilledButton>(_save).onPressed, isNull);
  _expectNoOtherWrites(app);
  expect(tester.takeException(), isNull);
}

void _expectNoOtherWrites(SafeApp app) {
  expect(app.fanPresetRequests, isEmpty);
  expect(app.requests, isEmpty);
  expect(app.rapidChargingRequests, isEmpty);
  expect(app.platformProfileRequests, isEmpty);
  expect(app.powerLimitRequests, isEmpty);
}
