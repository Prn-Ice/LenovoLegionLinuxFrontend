import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('privilege error explains distros and copies NixOS config', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppErrorDialogListener(
            errorMessage:
                'Privileged command support is unavailable: pkexec must be setuid root',
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
    expect(find.textContaining('enablePkexecWrapper = true'), findsOneWidget);

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
            errorMessage:
                'Privileged command support is unavailable: pkexec must be setuid root',
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
}
