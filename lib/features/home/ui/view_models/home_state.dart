import 'package:equatable/equatable.dart';

import '../../../auth/domain/models/user_session.dart';

const _unset = Object();

final class HomeState extends Equatable {
  const HomeState({
    required this.session,
    this.filtersExpanded = false,
    this.roomListExpanded = true,
    this.sessionWarningDismissed = false,
    this.threadOpen = false,
    this.panesOverThreadWidth,
  });

  final UserSession session;

  final bool filtersExpanded;

  final bool roomListExpanded;

  final bool sessionWarningDismissed;

  final bool threadOpen;

  // Lista ou filtros abertos à mão com a thread aberta ficam, com a thread por cima, enquanto a janela tiver ao menos esta largura.
  final double? panesOverThreadWidth;

  bool get showSessionWarning =>
      !session.sessionSaved && !sessionWarningDismissed;

  HomeState copyWith({
    bool? filtersExpanded,
    bool? roomListExpanded,
    bool? sessionWarningDismissed,
    bool? threadOpen,
    Object? panesOverThreadWidth = _unset,
  }) => HomeState(
    session: session,
    filtersExpanded: filtersExpanded ?? this.filtersExpanded,
    roomListExpanded: roomListExpanded ?? this.roomListExpanded,
    sessionWarningDismissed:
        sessionWarningDismissed ?? this.sessionWarningDismissed,
    threadOpen: threadOpen ?? this.threadOpen,
    panesOverThreadWidth: identical(panesOverThreadWidth, _unset)
        ? this.panesOverThreadWidth
        : panesOverThreadWidth as double?,
  );

  @override
  List<Object?> get props => [
    session,
    filtersExpanded,
    roomListExpanded,
    sessionWarningDismissed,
    threadOpen,
    panesOverThreadWidth,
  ];
}
