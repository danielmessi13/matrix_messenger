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

  void expandFilters({required double width}) => emit(
    state.copyWith(
      filtersExpanded: true,
      panesOverThreadWidth: state.threadOpen ? width : null,
    ),
  );

  void expandRoomList({required double width}) => emit(
    state.copyWith(
      roomListExpanded: true,
      panesOverThreadWidth: state.threadOpen ? width : null,
    ),
  );

  // Vem do painel da conversa, que pode avisar depois do logout fechar este ViewModel.
  void threadVisibilityChanged(bool open) {
    if (isClosed) return;
    emit(state.copyWith(threadOpen: open, panesOverThreadWidth: null));
  }

  void dismissSessionWarning() =>
      emit(state.copyWith(sessionWarningDismissed: true));
}
