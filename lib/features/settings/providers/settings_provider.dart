import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/settings_bloc.dart';
import '../bloc/settings_event.dart';
import '../bloc/settings_state.dart';
import '../repository/settings_repository.dart';
import '../repository/appearance_store.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(
    controlClient: ref.watch(legionControlClientProvider),
  );
});

// main supplies the opened Hive store before building the app. Headless users
// and existing repository-only tests can deliberately keep in-memory settings.
final appearanceStoreProvider = Provider<AppearanceStore?>((ref) => null);

final settingsBlocProvider =
    BlocProvider.autoDispose<SettingsBloc, SettingsState>((ref) {
      final repository = ref.watch(settingsRepositoryProvider);
      return SettingsBloc(
        repository: repository,
        appearanceStore: ref.watch(appearanceStoreProvider),
      )..add(const SettingsStarted());
    });
