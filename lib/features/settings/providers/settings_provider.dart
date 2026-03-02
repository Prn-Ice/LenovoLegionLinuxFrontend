import 'package:riverbloc/riverbloc.dart';

import '../bloc/settings_bloc.dart';
import '../bloc/settings_event.dart';
import '../bloc/settings_state.dart';
import '../repository/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

final settingsBlocProvider =
    BlocProvider.autoDispose<SettingsBloc, SettingsState>((ref) {
      final repository = ref.watch(settingsRepositoryProvider);
      return SettingsBloc(repository: repository)..add(const SettingsStarted());
    });
