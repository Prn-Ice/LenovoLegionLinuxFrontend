import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../features/navigation/view/navigation_shell.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../../features/settings/models/appearance_theme.dart';
import '../../features/dashboard/providers/dashboard_provider.dart';

class LegionFrontendApp extends ConsumerWidget {
  const LegionFrontendApp({super.key, this.home = const NavigationShell()});

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsBlocProvider);
    final mode = settings.accentFollowsPowerMode
        ? ref.watch(dashboardBlocProvider).snapshot.status.powerProfile
        : null;
    return YaruTheme(
      data: settings.yaruVariant != null
          ? YaruThemeData(variant: settings.yaruVariant)
          : const YaruThemeData(),
      builder: (context, yaru, child) {
        final themes = appearanceThemes(settings, mode, yaru);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Lenovo Legion Linux',
          themeMode: settings.themeMode,
          theme: themes.theme,
          darkTheme: themes.darkTheme,
          home: home,
        );
      },
    );
  }
}
