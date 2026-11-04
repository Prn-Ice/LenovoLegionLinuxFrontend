import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/widgets/surface_card.dart';
import 'package:yaru/yaru.dart';

Finder switchInCard(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(SurfaceCard)),
  matching: find.byType(YaruSwitch),
);

Future<void> waitFor(
  WidgetTester tester,
  bool Function() ready, {
  required String description,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      debugDumpApp();
      fail('Timed out waiting for $description after 15 seconds');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}
