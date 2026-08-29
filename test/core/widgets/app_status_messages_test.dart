import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/widgets/app_shell_components.dart';

void main() {
  testWidgets('success notices dismiss automatically', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppStatusMessages(noticeMessage: 'Power mode updated.'),
        ),
      ),
    );

    expect(find.text('Power mode updated.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('Power mode updated.'), findsNothing);
  });

  testWidgets('errors persist until dismissed', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppStatusMessages(errorMessage: 'Write failed.')),
      ),
    );

    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Write failed.'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('Write failed.'), findsNothing);
  });
}
