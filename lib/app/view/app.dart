import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../features/navigation/view/navigation_shell.dart';

class LegionFrontendApp extends StatelessWidget {
  const LegionFrontendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
      builder: (context, yaru, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Lenovo Legion Linux',
          themeMode: ThemeMode.system,
          theme: yaru.theme,
          darkTheme: yaru.darkTheme,
          home: const NavigationShell(),
        );
      },
    );
  }
}
