import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:legion_frontend/app/app.dart';
import 'package:legion_frontend/features/about/view/about_page.dart';

void main() {
  testWidgets('renders navigation shell and dashboard actions', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LegionFrontendApp()));

    expect(find.text('Power'), findsWidgets);
    expect(find.text('Power Profile'), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
  });

  testWidgets('renders diagnostics page', (tester) async {
    // Use a tall surface so all sidebar items fit without scrolling.
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ProviderScope(child: LegionFrontendApp()));

    await tester.tap(find.text('Diagnostics').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // TODO(Task 21): update to DiagnosticsPage when diagnostics page is implemented
    expect(find.byType(AboutPage), findsOneWidget);
  });
}
