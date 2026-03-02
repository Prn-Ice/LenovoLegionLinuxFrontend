import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/fans_bloc.dart';
import '../bloc/fans_event.dart';
import '../bloc/fans_state.dart';
import '../repository/fans_repository.dart';

final fansRepositoryProvider = Provider<FansRepository>((ref) {
  final sysfsService = ref.watch(legionSysfsServiceProvider);
  final cliService = ref.watch(legionCliServiceProvider);

  return FansRepository(sysfsService: sysfsService, cliService: cliService);
});

final fansBlocProvider = BlocProvider.autoDispose<FansBloc, FansState>((ref) {
  final repository = ref.watch(fansRepositoryProvider);
  return FansBloc(repository: repository)..add(const FansStarted());
});
