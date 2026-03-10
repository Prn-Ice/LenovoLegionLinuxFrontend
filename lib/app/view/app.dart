import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../features/navigation/view/navigation_shell.dart';
import '../../features/settings/providers/settings_provider.dart';

class LegionFrontendApp extends ConsumerWidget {
  const LegionFrontendApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsBlocProvider);
    return YaruTheme(
      data: settings.yaruVariant != null
          ? YaruThemeData(variant: settings.yaruVariant)
          : const YaruThemeData(),
      builder: (context, yaru, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Lenovo Legion Linux',
          themeMode: settings.themeMode,
          theme: yaru.theme,
          darkTheme: yaru.darkTheme,
          home: const NavigationShell(),
        );
      },
    );
  }
}
