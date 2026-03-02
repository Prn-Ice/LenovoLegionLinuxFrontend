import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/about_bloc.dart';
import '../bloc/about_event.dart';
import '../bloc/about_state.dart';
import '../repository/about_repository.dart';

final aboutRepositoryProvider = Provider<AboutRepository>((ref) {
  final sysfs = ref.watch(legionSysfsServiceProvider);
  final cli = ref.watch(legionCliServiceProvider);
  final bridge = ref.watch(legionBridgeServiceProvider);
  return AboutRepository(sysfs: sysfs, cli: cli, bridge: bridge);
});

final aboutBlocProvider = BlocProvider.autoDispose<AboutBloc, AboutState>((
  ref,
) {
  final repository = ref.watch(aboutRepositoryProvider);
  return AboutBloc(repository: repository)..add(const AboutStarted());
});
