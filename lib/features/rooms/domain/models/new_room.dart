import 'package:equatable/equatable.dart';

final class NewRoom extends Equatable {
  const NewRoom({
    required this.name,
    this.topic,
    required this.isPublic,
    this.invites = const [],
  });

  final String name;

  final String? topic;

  final bool isPublic;

  final List<String> invites;

  @override
  List<Object?> get props => [name, topic, isPublic, invites];
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

  final List<String> failedInvites;

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
