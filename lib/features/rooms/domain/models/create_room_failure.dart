enum CreateRoomFailureType { network, unknown }

class CreateRoomFailure implements Exception {
  const CreateRoomFailure(this.type, [this.details]);

  final CreateRoomFailureType type;

  final String? details;

  @override
  String toString() =>
      'CreateRoomFailure($type${details == null ? '' : ': $details'})';
}
