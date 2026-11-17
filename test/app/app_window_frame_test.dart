import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:legion_frontend/app/view/app_window_frame.dart';
import 'package:yaru/yaru.dart';

void main() {
  testWidgets('window corners clear on restore and fill when expanded', (
    tester,
  ) async {
    final states = StreamController<YaruWindowState>();
    addTearDown(states.close);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox(
              width: 80,
              height: 80,
              child: AppWindowFrame(
                windowStates: states.stream,
                child: const ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> checkCorners(YaruWindowState state, int alpha) async {
      states.add(state);
      await tester.pumpAndSettle();
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        for (final (x, y) in [(0, 0), (79, 0), (0, 79), (79, 79)]) {
          expect(pixels.getUint8((y * 80 + x) * 4 + 3), alpha);
        }
        expect(pixels.getUint8((40 * 80 + 40) * 4 + 3), 255);
        image.dispose();
      });
    }

    await checkCorners(const YaruWindowState(isMaximized: false), 0);
    await checkCorners(const YaruWindowState(isMaximized: true), 255);
    await checkCorners(const YaruWindowState(isFullscreen: true), 255);
    await checkCorners(
      const YaruWindowState(isMaximized: false, isFullscreen: false),
      0,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(states.hasListener, isFalse);
  });
}
