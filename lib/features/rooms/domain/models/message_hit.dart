import 'package:equatable/equatable.dart';

class MessageHit extends Equatable {
  const MessageHit({
    required this.roomId,
    required this.roomName,
    this.isDirect = false,
    required this.eventId,
    required this.senderName,
    this.isOwn = false,
    required this.body,
    required this.timestamp,
  });

  final String roomId;

  final String roomName;

  final bool isDirect;

  final String eventId;

  final String senderName;

  final bool isOwn;

  final String body;

  final DateTime timestamp;

  @override
  List<Object?> get props => [
    roomId,
    roomName,
    isDirect,
    eventId,
    senderName,
    isOwn,
    body,
    timestamp,
  ];
}

class MessageSearchPage extends Equatable {
  const MessageSearchPage({required this.hits, this.nextBatch});

  final List<MessageHit> hits;

  final String? nextBatch;

  @override
  List<Object?> get props => [hits, nextBatch];
}
