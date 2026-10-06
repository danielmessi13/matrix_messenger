enum MessageSearchFailureType { network, unknown }

class MessageSearchFailure implements Exception {
  const MessageSearchFailure(this.type, [this.details]);

  final MessageSearchFailureType type;

  final String? details;

  @override
  String toString() =>
      'MessageSearchFailure($type${details == null ? '' : ': $details'})';
}
