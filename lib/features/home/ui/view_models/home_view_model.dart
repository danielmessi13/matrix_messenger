import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../auth/domain/models/user_session.dart';
import 'home_state.dart';

class HomeViewModel extends Cubit<HomeState> {
  HomeViewModel(UserSession session, {bool roomListExpanded = true})
    : super(HomeState(session: session, roomListExpanded: roomListExpanded));

  void toggleFilters() =>
      emit(state.copyWith(filtersExpanded: !state.filtersExpanded));

  void toggleRoomList() =>
      emit(state.copyWith(roomListExpanded: !state.roomListExpanded));

  void dismissSessionWarning() =>
      emit(state.copyWith(sessionWarningDismissed: true));
}
