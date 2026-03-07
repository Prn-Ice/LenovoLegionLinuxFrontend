import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/boot_logo_bloc.dart';
import '../bloc/boot_logo_event.dart';
import '../bloc/boot_logo_state.dart';
import '../repository/boot_logo_repository.dart';

final bootLogoRepositoryProvider = Provider<BootLogoRepository>((ref) {
  final bridgeService = ref.watch(legionBridgeServiceProvider);
  return BootLogoRepository(bridgeService: bridgeService);
});

final bootLogoBlocProvider =
    BlocProvider.autoDispose<BootLogoBloc, BootLogoState>((ref) {
      final repository = ref.watch(bootLogoRepositoryProvider);
      return BootLogoBloc(repository: repository)..add(const BootLogoStarted());
    });
