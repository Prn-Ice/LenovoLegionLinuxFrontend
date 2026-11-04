import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/app_failure.dart';
import 'package:legion_frontend/core/widgets/app_shell_components.dart';

void main() {
  testWidgets('error opens a modal dialog and remains until closed', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppErrorDialogListener(
            errorMessage: 'Write failed.',
            child: Text('Page content'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Action could not be completed'), findsOneWidget);
    expect(find.text('Write failed.'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Write failed.'), findsNothing);
  });

  testWidgets('control setup error explains distros and copies NixOS config', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppErrorDialogListener(
            errorMessage: AppFailure(
              'The legion-control service could not provide privileged access.',
              kind: AppFailureKind.privilegeSetup,
            ),
            child: Text('Page content'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Privileged access needs setup'), findsOneWidget);
    expect(find.text('What this means'), findsOneWidget);
    expect(find.text('NixOS'), findsOneWidget);
    expect(find.text('Other Linux distributions'), findsOneWidget);
    expect(find.textContaining('services.legionControl ='), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('privilege dialog remains usable in a compact window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppErrorDialogListener(
            errorMessage: AppFailure(
              'The legion-control service could not provide privileged access.',
              kind: AppFailureKind.privilegeSetup,
            ),
            child: Text('Page content'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('classified graphics failures use consequence-specific titles', (
    tester,
  ) async {
    for (final failure in {
      AppFailure(
        'Backend wording changed.',
        kind: AppFailureKind.graphicsBlocked,
      ): 'Graphics change blocked',
      AppFailure(
        'Backend wording changed.',
        kind: AppFailureKind.graphicsPending,
      ): 'Graphics policy did not settle',
    }.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppErrorDialog(message: failure.key)),
        ),
      );

      expect(find.text(failure.value), findsOneWidget);
      expect(find.text(failure.key.message), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('English recognition phrases do not classify plain text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppErrorDialog(
            message:
                'legion-control service is not configured; effective GPU topology did not settle',
          ),
        ),
      ),
    );
    expect(find.text('Action could not be completed'), findsOneWidget);
    expect(find.text('NixOS'), findsNothing);
  });

  testWidgets('queues a different kind with the same text without stacking', (
    tester,
  ) async {
    final failure = ValueNotifier<AppFailure?>(
      const AppFailure('Same text', kind: AppFailureKind.graphicsBlocked),
    );
    addTearDown(failure.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<AppFailure?>(
            valueListenable: failure,
            builder: (_, value, _) => AppErrorDialogListener(
              errorMessage: value,
              child: const Text('Page content'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    failure.value = const AppFailure(
      'Same text',
      kind: AppFailureKind.graphicsPending,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Graphics change blocked'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Graphics policy did not settle'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    failure.value = const AppFailure(
      'Same text',
      kind: AppFailureKind.graphicsPending,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
