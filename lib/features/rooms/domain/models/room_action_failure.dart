enum RoomActionFailureType {
  notFound,
  forbidden,
  network,
  invalidUserId,
  unverifiedDevice,
  unknown,
}

class RoomActionFailure implements Exception {
  const RoomActionFailure(this.type, [this.details]);

  final RoomActionFailureType type;

  final String? details;

  @override
  String toString() =>
      'RoomActionFailure($type${details == null ? '' : ': $details'})';
}
