import 'package:equatable/equatable.dart';

import '../../../rooms/domain/models/room.dart';

class RoomNotification extends Equatable {
  const RoomNotification({
    required this.roomId,
    required this.roomName,
    this.isDirect = false,
    this.isInvite = false,
    required this.senderName,
    this.kind = LatestMessageKind.text,
    this.body,
    required this.timestamp,
  });

  final String roomId;

  final String roomName;

  final bool isDirect;

  final bool isInvite;

  final String senderName;

  final LatestMessageKind kind;

  final String? body;

  final DateTime timestamp;

  @override
  List<Object?> get props => [
    roomId,
    roomName,
    isDirect,
    isInvite,
    senderName,
    kind,
    body,
    timestamp,
  ];
}
