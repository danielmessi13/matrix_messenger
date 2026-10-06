import 'package:equatable/equatable.dart';

import 'failed_invite.dart';

final class NewRoom extends Equatable {
  const NewRoom({
    required this.name,
    this.topic,
    required this.isPublic,
    this.invites = const [],
    this.shareHistory = true,
  });

  final String name;

  final String? topic;

  final bool isPublic;

  final List<String> invites;

  // Só vale para sala privada: convidados recebem as chaves das mensagens anteriores.
  final bool shareHistory;

  @override
  List<Object?> get props => [name, topic, isPublic, invites, shareHistory];
}

// O diálogo de nova sala devolve a sala a abrir, criada ou em que se entrou.
sealed class NewRoomResult extends Equatable {
  const NewRoomResult();

  String get roomId;
}

final class CreatedRoom extends NewRoomResult {
  const CreatedRoom({required this.roomId, this.failedInvites = const []});

  @override
  final String roomId;

  final List<FailedInvite> failedInvites;

  @override
  List<Object?> get props => [roomId, failedInvites];
}

final class JoinedRoom extends NewRoomResult {
  const JoinedRoom(this.roomId);

  @override
  final String roomId;

  @override
  List<Object?> get props => [roomId];
}
