import 'package:equatable/equatable.dart';

import '../../../auth/domain/models/user_session.dart';

final class HomeState extends Equatable {
  const HomeState({
    required this.session,
    this.filtersExpanded = false,
    this.roomListExpanded = true,
    this.sessionWarningDismissed = false,
  });

  final UserSession session;

  final bool filtersExpanded;

  final bool roomListExpanded;

  final bool sessionWarningDismissed;

  bool get showSessionWarning =>
      !session.sessionSaved && !sessionWarningDismissed;

  HomeState copyWith({
    bool? filtersExpanded,
    bool? roomListExpanded,
    bool? sessionWarningDismissed,
  }) => HomeState(
    session: session,
    filtersExpanded: filtersExpanded ?? this.filtersExpanded,
    roomListExpanded: roomListExpanded ?? this.roomListExpanded,
    sessionWarningDismissed:
        sessionWarningDismissed ?? this.sessionWarningDismissed,
  );

  @override
  List<Object?> get props => [
    session,
    filtersExpanded,
    roomListExpanded,
    sessionWarningDismissed,
  ];
}
