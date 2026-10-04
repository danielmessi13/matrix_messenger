import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../auth/domain/models/user_session.dart';
import 'home_state.dart';

// TODO: expor a lista de salas.
class HomeViewModel extends Cubit<HomeState> {
  HomeViewModel(UserSession session) : super(HomeState(session: session));
}
