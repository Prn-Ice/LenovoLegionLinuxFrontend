import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/display_bloc.dart';
import '../bloc/display_event.dart';
import '../bloc/display_state.dart';
import '../repository/display_repository.dart';

final displayRepositoryProvider = Provider<DisplayRepository>((ref) {
  final sysfsService = ref.watch(legionSysfsServiceProvider);
  final bridgeService = ref.watch(legionBridgeServiceProvider);
  final xrandrService = ref.watch(xrandrServiceProvider);

  return DisplayRepository(
    sysfsService: sysfsService,
    bridgeService: bridgeService,
    xrandrService: xrandrService,
  );
});

final displayBlocProvider =
    BlocProvider.autoDispose<DisplayBloc, DisplayState>((ref) {
      final repository = ref.watch(displayRepositoryProvider);
      return DisplayBloc(repository: repository)..add(const DisplayStarted());
    });
