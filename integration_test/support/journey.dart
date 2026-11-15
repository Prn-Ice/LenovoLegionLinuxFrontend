import 'package:material_ui/material_ui.dart';
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
      // Print before the tree dump. The native test log can interleave or
      // truncate the dump, but this marker preserves the failed condition.
      // ignore: avoid_print
      print('WAIT_FOR_TIMEOUT: $description');
      debugDumpApp();
      fail('Timed out waiting for $description after 15 seconds');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}
