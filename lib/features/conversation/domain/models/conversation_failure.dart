enum ConversationFailureType {
  roomNotFound,
  messageNotFound,
  invalidImage,
  network,
  unknown,
}

class ConversationFailure implements Exception {
  const ConversationFailure(this.type, [this.details]);

  final ConversationFailureType type;

  final String? details;

  @override
  String toString() =>
      'ConversationFailure($type${details == null ? '' : ': $details'})';
}
