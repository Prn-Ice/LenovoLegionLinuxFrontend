// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:ui' show AppExitType;

import 'package:flutter/services.dart';
import 'package:flutter/src/widgets/_window_linux.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yaru/yaru.dart';

import 'window_resize_border.dart';

class WindowPreviewApp extends StatefulWidget {
  const WindowPreviewApp({super.key, required this.window});

  final WindowControllerLinux window;

  @override
  State<WindowPreviewApp> createState() => _WindowPreviewAppState();
}

class _WindowPreviewAppState extends State<WindowPreviewApp> {
  ThemeMode _themeMode = ThemeMode.system;

  WindowControllerLinux get window => widget.window;

  void restoreWindow() {
    window.setFullscreen(false);
    window.setMaximized(false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: window,
    builder: (context, child) {
      final rounded = !window.isMaximized && !window.isFullscreen;
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: createYaruLightTheme(primaryColor: const Color(0xFF555555)),
        darkTheme: createYaruDarkTheme(primaryColor: const Color(0xFFFAFAFA)),
        themeMode: _themeMode,
        builder: (context, child) {
          // GTK reports a 1 px surface before the first size notification.
          final physicalSize =
              MediaQuery.sizeOf(context) *
              MediaQuery.devicePixelRatioOf(context);
          if (physicalSize.shortestSide <= 1) {
            return const SizedBox.shrink();
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(rounded ? 8 : 0),
            child: child!,
          );
        },
        home: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f11): () =>
                window.setFullscreen(!window.isFullscreen),
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                window.setFullscreen(false),
          },
          child: Focus(
            autofocus: true,
            child: WindowResizeBorder(
              window: window,
              enabled: rounded,
              child: Scaffold(
                appBar: YaruTitleBar(
                  title: const Text('Window preview'),
                  centerTitle: false,
                  isActive: window.isActivated,
                  isClosable: true,
                  isMinimizable: true,
                  isMaximizable: !window.isMaximized && !window.isFullscreen,
                  isRestorable: window.isMaximized || window.isFullscreen,
                  isDraggable: !window.isFullscreen,
                  onDrag: (_) => window.beginMoveDrag(button: 1),
                  onDoubleTap: (_) => window.setMaximized(!window.isMaximized),
                  onMaximize: (_) => window.setMaximized(true),
                  onRestore: (_) => restoreWindow(),
                  onMinimize: (_) => window.setMinimized(true),
                  onClose: (_) => ServicesBinding.instance.exitApplication(
                    AppExitType.required,
                  ),
                ),
                body: Builder(builder: buildWindowControls),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget buildWindowControls(BuildContext context) {
    final theme = Theme.of(context);
    final state = window.isFullscreen
        ? 'Fullscreen'
        : window.isMaximized
        ? 'Maximized'
        : 'Restored';
    final size = MediaQuery.sizeOf(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Try the window', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'A separate preview of Flutter’s experimental Linux window API, '
          'using Legion’s Yaru theme.',
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: () => window.setMaximized(true),
              icon: const Icon(Icons.crop_square),
              label: const Text('Maximize'),
            ),
            OutlinedButton.icon(
              onPressed: () => window.setFullscreen(true),
              icon: const Icon(Icons.fullscreen),
              label: const Text('Fullscreen'),
            ),
            OutlinedButton.icon(
              onPressed: restoreWindow,
              icon: const Icon(Icons.fullscreen_exit),
              label: const Text('Restore'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Window state'),
          subtitle: Text(
            '$state · ${size.width.round()} × ${size.height.round()}',
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Corners'),
          subtitle: Text(
            window.isMaximized || window.isFullscreen
                ? 'Square, so the window fills every edge.'
                : 'Rounded by 8 px; transparency is not yet verified.',
          ),
        ),
        const Divider(),
        const SizedBox(height: 16),
        Text('Appearance', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in ThemeMode.values)
              ChoiceChip(
                label: Text(switch (mode) {
                  ThemeMode.system => 'System',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                }),
                selected: _themeMode == mode,
                onSelected: (_) => setState(() => _themeMode = mode),
              ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Drag the title bar to move. Drag an edge to resize. '
          'F11 toggles fullscreen; Escape leaves it.',
        ),
        const SizedBox(height: 8),
        Text(
          'This preview controls only this window.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
