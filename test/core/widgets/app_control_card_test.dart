import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/widgets/app_shell_components.dart';
import 'package:yaru/yaru.dart';

void main() {
  testWidgets('AppControlCard renders icon and title', (tester) async {
    await tester.pumpWidget(
      YaruTheme(
        builder: (context, yaru, _) => MaterialApp(
          theme: yaru.theme,
          home: Scaffold(
            body: AppControlCard(
              icon: Icons.bolt,
              title: 'Power',
              children: const [Text('content')],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.bolt), findsOneWidget);
    expect(find.text('Power'), findsOneWidget);
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('AppControlCard renders description when provided', (tester) async {
    await tester.pumpWidget(
      YaruTheme(
        builder: (context, yaru, _) => MaterialApp(
          theme: yaru.theme,
          home: Scaffold(
            body: AppControlCard(
              icon: Icons.bolt,
              title: 'Power',
              description: 'Manage performance',
              children: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Manage performance'), findsOneWidget);
  });

  testWidgets('DashboardCard renders icon and title', (tester) async {
    await tester.pumpWidget(
      YaruTheme(
        builder: (context, yaru, _) => MaterialApp(
          theme: yaru.theme,
          home: Scaffold(
            body: DashboardCard(
              icon: Icons.thermostat,
              title: 'Temperature',
              children: const [Text('61°C')],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.thermostat), findsOneWidget);
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('61°C'), findsOneWidget);
  });
}
