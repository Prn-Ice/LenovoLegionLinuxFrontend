// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:flutter/gestures.dart';
import 'package:flutter/src/widgets/_window_linux.dart';
import 'package:flutter/widgets.dart';

/// Gives the undecorated preview native edge-resize gestures.
class WindowResizeBorder extends StatelessWidget {
  const WindowResizeBorder({
    super.key,
    required this.window,
    required this.enabled,
    required this.child,
  });

  final WindowControllerLinux window;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      if (enabled) ...[
        edge(WindowDragEdge.north, top: 0, left: 8, right: 8),
        edge(WindowDragEdge.south, bottom: 0, left: 8, right: 8),
        edge(WindowDragEdge.west, left: 0, top: 8, bottom: 8),
        edge(WindowDragEdge.east, right: 0, top: 8, bottom: 8),
        edge(WindowDragEdge.northWest, top: 0, left: 0),
        edge(WindowDragEdge.northEast, top: 0, right: 0),
        edge(WindowDragEdge.southWest, bottom: 0, left: 0),
        edge(WindowDragEdge.southEast, bottom: 0, right: 0),
      ],
    ],
  );

  Widget edge(
    WindowDragEdge edge, {
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) => Positioned(
    top: top,
    bottom: bottom,
    left: left,
    right: right,
    width: left == null || right == null ? 8 : null,
    height: top == null || bottom == null ? 8 : null,
    child: MouseRegion(
      cursor: switch (edge) {
        WindowDragEdge.north ||
        WindowDragEdge.south => SystemMouseCursors.resizeUpDown,
        WindowDragEdge.east ||
        WindowDragEdge.west => SystemMouseCursors.resizeLeftRight,
        WindowDragEdge.northWest ||
        WindowDragEdge.southEast => SystemMouseCursors.resizeUpLeftDownRight,
        WindowDragEdge.northEast ||
        WindowDragEdge.southWest => SystemMouseCursors.resizeUpRightDownLeft,
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.buttons == kPrimaryButton) {
            window.beginResizeDrag(edge: edge, button: 1);
          }
        },
      ),
    ),
  );
}
