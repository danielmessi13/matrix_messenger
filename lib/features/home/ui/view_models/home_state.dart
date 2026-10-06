import 'package:equatable/equatable.dart';

import '../../../auth/domain/models/user_session.dart';
import '../../../rooms/domain/models/failed_invite.dart';

const _unset = Object();

final class HomeState extends Equatable {
  const HomeState({
    required this.session,
    this.filtersExpanded = false,
    this.roomListExpanded = true,
    this.sessionWarningDismissed = false,
    this.threadOpen = false,
    this.openThreadId,
    this.panesOverThreadWidth,
    this.failedInvites = const [],
  });

  final UserSession session;

  final bool filtersExpanded;

  final bool roomListExpanded;

  final bool sessionWarningDismissed;

  final bool threadOpen;

  final String? openThreadId;

  // Lista ou filtros abertos à mão com a thread aberta ficam, com a thread por cima, enquanto a janela tiver ao menos esta largura.
  final double? panesOverThreadWidth;

  final List<FailedInvite> failedInvites;

  bool get showSessionWarning =>
      !session.sessionSaved && !sessionWarningDismissed;

  HomeState copyWith({
    bool? filtersExpanded,
    bool? roomListExpanded,
    bool? sessionWarningDismissed,
    bool? threadOpen,
    Object? openThreadId = _unset,
    Object? panesOverThreadWidth = _unset,
    List<FailedInvite>? failedInvites,
  }) => HomeState(
    session: session,
    filtersExpanded: filtersExpanded ?? this.filtersExpanded,
    roomListExpanded: roomListExpanded ?? this.roomListExpanded,
    sessionWarningDismissed:
        sessionWarningDismissed ?? this.sessionWarningDismissed,
    threadOpen: threadOpen ?? this.threadOpen,
    openThreadId: identical(openThreadId, _unset)
        ? this.openThreadId
        : openThreadId as String?,
    panesOverThreadWidth: identical(panesOverThreadWidth, _unset)
        ? this.panesOverThreadWidth
        : panesOverThreadWidth as double?,
    failedInvites: failedInvites ?? this.failedInvites,
  );

  @override
  List<Object?> get props => [
    session,
    filtersExpanded,
    roomListExpanded,
    sessionWarningDismissed,
    threadOpen,
    openThreadId,
    panesOverThreadWidth,
    failedInvites,
  ];
}
