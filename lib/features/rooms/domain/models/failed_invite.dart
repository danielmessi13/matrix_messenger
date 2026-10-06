import 'package:equatable/equatable.dart';

import 'room_action_failure.dart';

final class FailedInvite extends Equatable {
  const FailedInvite(this.userId, this.type);

  final String userId;

  final RoomActionFailureType type;

  @override
  List<Object?> get props => [userId, type];
}
