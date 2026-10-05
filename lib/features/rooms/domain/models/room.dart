import 'package:equatable/equatable.dart';

enum LatestMessageKind { text, image, file, encrypted, other }

class LatestMessage extends Equatable {
  const LatestMessage({
    required this.senderName,
    required this.isOwn,
    required this.kind,
    this.body,
    required this.timestamp,
  });

  final String senderName;

  final bool isOwn;

  final LatestMessageKind kind;

  final String? body;

  final DateTime timestamp;

  @override
  List<Object?> get props => [senderName, isOwn, kind, body, timestamp];
}

class Room extends Equatable {
  const Room({
    required this.id,
    required this.name,
    this.isDirect = false,
    this.isInvite = false,
    this.unreadMessages = 0,
    this.unreadMentions = 0,
    this.memberCount = 0,
    this.heroes = const [],
    this.latest,
  });

  final String id;

  /// Vazio quando a sala não tem nome nem outros membros.
  final String name;

  final bool isDirect;

  final bool isInvite;

  final int unreadMessages;

  final int unreadMentions;

  final int memberCount;

  final List<String> heroes;

  final LatestMessage? latest;

  @override
  List<Object?> get props => [
    id,
    name,
    isDirect,
    isInvite,
    unreadMessages,
    unreadMentions,
    memberCount,
    heroes,
    latest,
  ];
}
