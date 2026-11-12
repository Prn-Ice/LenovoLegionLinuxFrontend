import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/app_failure.dart';
import 'package:legion_frontend/core/widgets/app_shell_components.dart';

void main() {
  testWidgets('portable setup recovery avoids installed service instructions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppErrorDialog(
            message: AppFailure(
              'CLI selection changed',
              kind: AppFailureKind.portableSetup,
              details: 'Canonical CLI mismatch',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Temporary hardware access needs setup'), findsOneWidget);
    expect(find.textContaining('reopen the app'), findsWidgets);
    expect(find.text('NixOS'), findsNothing);
    expect(find.text('Copy configuration'), findsNothing);
    expect(find.text('Technical details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final embedded in [false, true]) {
    testWidgets('displays and copies raw details once (embedded: $embedded)', (
      tester,
    ) async {
      const raw = 'raw error\n  diagnostic context';
      final failure = AppFailure(
        embedded ? 'Short message\n\n$raw' : 'Short message',
        details: raw,
      );
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppErrorDialog(message: failure)),
        ),
      );
      expect(find.textContaining('Short message'), findsOneWidget);
      expect(find.textContaining(raw), findsOneWidget);
      await tester.tap(find.text('Copy details'));
      await tester.pumpAndSettle();
      expect(copied, 'Short message\n\n$raw');
      expect(find.text('Copied'), findsOneWidget);
    });
  }

  testWidgets('error opens a modal dialog and remains until closed', (
    tester,
  ) async {
    AppFailure? dismissed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppErrorDialogListener(
            errorMessage: 'Write failed.',
            onErrorDismissed: (error) => dismissed = error,
            child: const Text('Page content'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Action could not be completed'), findsOneWidget);
    expect(find.text('Write failed.'), findsOneWidget);
    expect(dismissed, isNull);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Write failed.'), findsNothing);
    expect(dismissed?.message, 'Write failed.');
  });

  testWidgets('OpenRGB diagnostics stay usable in a compact window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppErrorDialogListener(
            errorMessage: AppFailure(
              'OpenRGB could not apply keyboard lighting. The keyboard may be partly updated. Check the OpenRGB connection and selected device, then retry.',
              kind: AppFailureKind.commandFailed,
              details:
                  'Command: ["openrgb", "-c", "${List.filled(200, 'FF3311').join(',')}"]\nExit code: 17\nDevice rejected the write',
            ),
            child: const Text('Lighting'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppErrorDialog), findsOneWidget);
    expect(find.text('Copy details').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Close').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(AppErrorDialog), findsNothing);
    expect(tester.takeException(), isNull);
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
        details: 'raw graphics diagnostic',
      ): 'Graphics mode was not changed',
      AppFailure(
        'Backend wording changed.',
        kind: AppFailureKind.graphicsPending,
        details: 'raw graphics diagnostic',
      ): 'Graphics mode switch incomplete',
    }.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppErrorDialog(message: failure.key)),
        ),
      );

      expect(find.text(failure.value), findsOneWidget);
      expect(find.text(failure.key.message), findsOneWidget);
      expect(find.text('raw graphics diagnostic'), findsOneWidget);
      expect(find.text('Technical details'), findsOneWidget);
      expect(find.textContaining('could not confirm'), findsNothing);
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

  testWidgets(
    'an incomplete graphics switch shows recovery once and keeps diagnostics separate',
    (tester) async {
      tester.view.physicalSize = const Size(420, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const recovery =
          'The setting for Integrated graphics only was saved, but the switch did not finish. Save your work and restart the laptop before trying another mode.';
      const diagnostic = 'driver exit status: 3';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppErrorDialog(
              message: AppFailure(
                recovery,
                kind: AppFailureKind.graphicsPending,
                details: diagnostic,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Graphics mode switch incomplete'), findsOneWidget);
      expect(find.text(recovery), findsOneWidget);
      expect(find.text(diagnostic), findsOneWidget);
      expect(find.text('Technical details'), findsOneWidget);
      expect(find.textContaining('could not confirm'), findsNothing);
      expect(
        find.textContaining('The requested action did not complete'),
        findsNothing,
      );
      expect(find.text('Close').hitTestable(), findsOneWidget);
      expect(find.text('Copy details').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
    expect(find.text('Graphics mode was not changed'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Graphics mode switch incomplete'), findsOneWidget);
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
