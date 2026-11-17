import 'package:material_ui/material_ui.dart';
import 'package:yaru/yaru.dart';

/// Clips the Flutter surface, which Wayland draws outside GTK's corner mask.
class AppWindowFrame extends StatefulWidget {
  const AppWindowFrame({super.key, required this.child, this.windowStates});

  final Widget child;
  final Stream<YaruWindowState>? windowStates;

  @override
  State<AppWindowFrame> createState() => _AppWindowFrameState();
}

class _AppWindowFrameState extends State<AppWindowFrame> {
  late final _windowStates = YaruWindow.states(context);

  @override
  Widget build(BuildContext context) => StreamBuilder<YaruWindowState>(
    stream: widget.windowStates ?? _windowStates,
    builder: (context, snapshot) {
      final state = snapshot.data;
      final rounded =
          state != null &&
          state.isMaximized != true &&
          state.isFullscreen != true;
      // Match the bundled libhandy Adwaita window mask, not a card radius.
      return ClipRRect(
        borderRadius: BorderRadius.circular(rounded ? 8 : 0),
        child: widget.child,
      );
    },
  );
}
