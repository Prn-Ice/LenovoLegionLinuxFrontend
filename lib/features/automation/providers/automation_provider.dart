import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/automation_bloc.dart';
import '../bloc/automation_event.dart';
import '../bloc/automation_state.dart';
import '../repository/automation_repository.dart';

final automationRepositoryProvider = Provider<AutomationRepository>((ref) {
  final sysfsService = ref.watch(legionSysfsServiceProvider);
  final cliService = ref.watch(legionCliServiceProvider);

  return AutomationRepository(
    sysfsService: sysfsService,
    cliService: cliService,
  );
});

final automationBlocProvider =
    BlocProvider.autoDispose<AutomationBloc, AutomationState>((ref) {
      final repository = ref.watch(automationRepositoryProvider);
      return AutomationBloc(repository: repository)
        ..add(const AutomationStarted());
    });
