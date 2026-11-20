// The window API is experimental and confined to this preview package.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:ui' show AppExitType;

import 'package:flutter/services.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_linux.dart';
import 'package:flutter/widgets.dart';

import 'window_preview_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runWidget(const WindowPreview());
}

class WindowPreview extends StatefulWidget {
  const WindowPreview({super.key});

  @override
  State<WindowPreview> createState() => _WindowPreviewState();
}

class _WindowPreviewState extends State<WindowPreview> {
  late final _window = createPreviewWindow();

  @override
  void dispose() {
    _window.destroy();
    _window.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Window(
    controller: _window,
    child: WindowPreviewApp(window: _window),
  );
}

WindowControllerLinux createPreviewWindow() {
  final window = WindowControllerLinux(
    owner: WidgetsBinding.instance.windowingOwner as WindowingOwnerLinux,
    decorated: false,
    title: 'Legion — Window preview',
    size: const Size(880, 620),
    constraints: const BoxConstraints(minWidth: 420, minHeight: 500),
    delegate: ExitOnClose(),
  );
  window.setAppPaintable(true);
  window.setBackgroundColor(const Color(0x00000000));
  return window;
}

class ExitOnClose with WindowControllerDelegate {
  @override
  void onWindowCloseRequested(WindowController controller) {
    ServicesBinding.instance.exitApplication(AppExitType.required);
  }
}
