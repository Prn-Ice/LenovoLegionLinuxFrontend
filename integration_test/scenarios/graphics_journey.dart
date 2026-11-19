import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:legion_frontend/core/widgets/app_shell_components.dart';
import 'package:legion_frontend/features/dgpu/providers/dgpu_provider.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_state.dart';
import 'package:legion_frontend/features/dgpu/view/dgpu_page.dart';
import 'package:legion_frontend/features/dgpu/models/graphics_mode.dart';

import '../support/journey.dart';
import '../support/safe_app.dart';
import '../support/safe_graphics.dart';

void main() {
  testWidgets(
    'cancelling a graphics change performs no authorization or write',
    (tester) async {
      final fixture = SafeGraphicsFixture();
      final app = await SafeApp.create();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await app.dispose();
      });
      await app.launch(additionalOverrides: safeGraphicsOverrides(fixture));
      await _openGraphics(tester);

      await _chooseMode(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(fixture.authorizations, 0);
      expect(fixture.requests, isEmpty);
      expect(fixture.writes, isEmpty);
      expect(fixture.selectedMode, GraphicsMode.hybrid);
    },
  );

  testWidgets(
    'confirmed graphics change uses typed control and status readback',
    (tester) async {
      final fixture = SafeGraphicsFixture()
        ..observedAfterWrite = (
          effective: DgpuTopology.detached,
          expected: DgpuTopology.detached,
        );
      final app = await SafeApp.create();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await app.dispose();
      });
      await app.launch(additionalOverrides: safeGraphicsOverrides(fixture));
      await _openGraphics(tester);

      final readsBeforeWrite = fixture.statusReads;
      await _chooseMode(tester);
      await tester.tap(find.text('Switch mode'));
      await waitFor(
        tester,
        () =>
            fixture.writes.contains(GraphicsMode.hybridIgpuOnly) &&
            !_state(tester).isApplying &&
            _state(tester).graphicsModeStatus?.selectedMode ==
                GraphicsMode.hybridIgpuOnly,
        description: 'graphics write and authoritative status readback',
      );

      expect(fixture.requests, [GraphicsMode.hybridIgpuOnly]);
      expect(fixture.writes, [GraphicsMode.hybridIgpuOnly]);
      expect(fixture.authorizations, 1);
      expect(fixture.selectedMode, GraphicsMode.hybridIgpuOnly);
      expect(fixture.statusReads, greaterThan(readsBeforeWrite));
      expect(
        _state(tester).graphicsModeStatus?.effectiveState,
        DgpuTopology.detached,
      );
      expect(
        _state(tester).graphicsModeStatus?.expectedState,
        DgpuTopology.detached,
      );
      expect(find.text('Not detected'), findsOneWidget);
    },
  );

  testWidgets(
    'renders effective topology separately from a pending selection',
    (tester) async {
      final fixture = SafeGraphicsFixture()
        ..expectedState = DgpuTopology.detached
        ..reconciliation = GraphicsReconciliation.needed;
      final app = await SafeApp.create();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await app.dispose();
      });
      await app.launch(additionalOverrides: safeGraphicsOverrides(fixture));
      await _openGraphics(tester);

      expect(find.text('Switch incomplete'), findsOneWidget);
      expect(find.text('Detected'), findsOneWidget);
      expect(fixture.selectedMode, GraphicsMode.hybrid);
      expect(fixture.effectiveState, DgpuTopology.attached);
      expect(fixture.writes, isEmpty);
    },
  );

  testWidgets('denied graphics authorization produces zero writes', (
    tester,
  ) async {
    final fixture = SafeGraphicsFixture()..failAuthorization = true;
    final app = await SafeApp.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });
    await app.launch(additionalOverrides: safeGraphicsOverrides(fixture));
    await _openGraphics(tester);

    await _chooseMode(tester);
    await tester.tap(find.text('Switch mode'));
    await waitFor(
      tester,
      () => find.byType(AppErrorDialog).evaluate().isNotEmpty,
      description: 'denied graphics authorization dialog',
    );
    await tester.pumpAndSettle();
    expect(fixture.authorizations, 1);
    await waitFor(
      tester,
      () => find.textContaining('Permission was denied').evaluate().isNotEmpty,
      description: 'graphics authorization failure',
    );

    expect(fixture.authorizations, 1);
    expect(fixture.requests, isEmpty);
    expect(fixture.writes, isEmpty);
  });

  testWidgets(
    'unavailable or unknown graphics status hides every write action',
    (tester) async {
      for (final configure in <void Function(SafeGraphicsFixture)>[
        (fixture) => fixture.statusUnavailable = true,
        (fixture) => fixture.returnUnknownStatus = true,
      ]) {
        final fixture = SafeGraphicsFixture();
        configure(fixture);
        final app = await SafeApp.create();
        await app.launch(additionalOverrides: safeGraphicsOverrides(fixture));
        await _openGraphicsPage(tester);
        await waitFor(
          tester,
          () => find
              .text(
                'Graphics status is unavailable. Use Refresh to reload it before changing modes.',
              )
              .evaluate()
              .isNotEmpty,
          description: 'fail-closed graphics status',
        );
        expect(
          find.byKey(const ValueKey('set-graphics-hybrid-igpu-only')),
          findsNothing,
        );
        expect(fixture.authorizations, 0);
        expect(fixture.requests, isEmpty);
        expect(fixture.writes, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await app.dispose();
      }
    },
  );
}

Future<void> _openGraphics(WidgetTester tester) async {
  await _openGraphicsPage(tester);
  await waitFor(
    tester,
    () => find
        .byKey(const ValueKey('set-graphics-hybrid-igpu-only'))
        .evaluate()
        .isNotEmpty,
    description: 'graphics mode controls',
  );
}

DgpuState _state(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(DgpuPage)))
        .read(dgpuBlocProvider);

Future<void> _chooseMode(WidgetTester tester) async {
  final control = find.byKey(const ValueKey('set-graphics-hybrid-igpu-only'));
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
  expect(find.text('Switch mode'), findsOneWidget);
}

Future<void> _openGraphicsPage(WidgetTester tester) async {
  final navigation = find.text('Discrete GPU').hitTestable();
  await waitFor(
    tester,
    () => navigation.evaluate().isNotEmpty,
    description: 'Discrete GPU navigation control',
  );
  await tester.tap(navigation.first);
  await waitFor(
    tester,
    () => find.byType(DgpuPage).evaluate().isNotEmpty,
    description: 'Graphics page navigation',
  );
  await tester.pumpAndSettle();
}
