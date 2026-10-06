enum JoinRoomFailureType { invalidLink, notFound, forbidden, network, unknown }

class JoinRoomFailure implements Exception {
  const JoinRoomFailure(this.type, [this.details]);

  final JoinRoomFailureType type;

  final String? details;

  @override
  String toString() =>
      'JoinRoomFailure($type${details == null ? '' : ': $details'})';
}
