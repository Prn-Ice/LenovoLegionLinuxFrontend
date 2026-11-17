import 'package:riverbloc/riverbloc.dart';

import '../bloc/settings_bloc.dart';
import '../bloc/settings_state.dart';
import '../repository/appearance_store.dart';

// main supplies the opened Hive store. Tests can keep in-memory preferences.
final appearanceStoreProvider = Provider<AppearanceStore?>((ref) => null);

final settingsBlocProvider =
    BlocProvider.autoDispose<SettingsBloc, SettingsState>((ref) {
      return SettingsBloc(appearanceStore: ref.watch(appearanceStoreProvider));
    });
