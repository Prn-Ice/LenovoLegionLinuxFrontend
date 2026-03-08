import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/dgpu_bloc.dart';
import '../bloc/dgpu_event.dart';
import '../bloc/dgpu_state.dart';
import '../repository/dgpu_repository.dart';

final dgpuRepositoryProvider = Provider<DgpuRepository>((ref) {
  final bridgeService = ref.watch(legionBridgeServiceProvider);
  return DgpuRepository(bridgeService: bridgeService);
});

final dgpuBlocProvider =
    BlocProvider.autoDispose<DgpuBloc, DgpuState>((ref) {
      final repository = ref.watch(dgpuRepositoryProvider);
      return DgpuBloc(repository: repository)..add(const DgpuStarted());
    });
