import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/dashboard/widgets/quick_controls.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  testWidgets('renders a title and subtitle for each control', (tester) async {
    await _pump(
      tester,
      QuickControls(
        accent: const Color(0xFFEC5F2A),
        controls: [
          QuickControl(
            icon: Icons.bolt,
            title: 'Rapid charge',
            subtitle: 'Charge to full as fast as possible',
            value: true,
            onChanged: (_) {},
          ),
          const QuickControl(
            icon: Icons.keyboard_outlined,
            title: 'Fn lock',
            subtitle: 'F-keys act as F1–F12 directly',
            value: false,
            onChanged: null, // unsupported / disabled
          ),
        ],
      ),
    );

    expect(find.text('Rapid charge'), findsOneWidget);
    expect(find.text('Charge to full as fast as possible'), findsOneWidget);
    expect(find.text('Fn lock'), findsOneWidget);
    expect(find.text('F-keys act as F1–F12 directly'), findsOneWidget);
  });
}
