import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import 'app/app.dart';

Future<void> main() async {
  await YaruWindowTitleBar.ensureInitialized();
  runApp(const ProviderScope(child: LegionFrontendApp()));
}
