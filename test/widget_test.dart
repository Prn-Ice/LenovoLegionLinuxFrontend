import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:legion_frontend/app/app.dart';
import 'package:legion_frontend/features/settings/view/settings_page.dart';

void main() {
  testWidgets('renders navigation shell and dashboard actions', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LegionFrontendApp()));

    expect(find.text('Power'), findsWidgets);
    expect(find.text('Power Profile'), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
  });

  testWidgets('renders diagnostics page', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LegionFrontendApp()));

    await tester.tap(find.text('Diagnostics').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(SettingsPage), findsOneWidget);
  });
}
