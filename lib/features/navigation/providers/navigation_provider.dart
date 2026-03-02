import 'package:riverbloc/riverbloc.dart';

import '../bloc/navigation_bloc.dart';
import '../bloc/navigation_state.dart';

final navigationBlocProvider = BlocProvider<NavigationBloc, NavigationState>(
  (ref) => NavigationBloc(),
);
