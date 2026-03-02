import 'package:flutter/material.dart';

import '../../features/navigation/view/navigation_shell.dart';

class LegionFrontendApp extends StatelessWidget {
  const LegionFrontendApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF15616D);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lenovo Legion Linux',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
      ),
      home: const NavigationShell(),
    );
  }
}
