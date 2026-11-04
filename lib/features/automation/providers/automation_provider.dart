import 'package:riverbloc/riverbloc.dart';

import '../bloc/automation_bloc.dart';
import '../bloc/automation_event.dart';
import '../bloc/automation_state.dart';
import '../repository/automation_repository.dart';

final automationRepositoryProvider = Provider<AutomationRepository>(
  (ref) => AutomationRepository(),
);

final automationBlocProvider =
    BlocProvider.autoDispose<AutomationBloc, AutomationState>((ref) {
      final repository = ref.watch(automationRepositoryProvider);
      return AutomationBloc(repository: repository)
        ..add(const AutomationStarted());
    });
