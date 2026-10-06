import 'package:equatable/equatable.dart';

import '../../../domain/models/room_action_failure.dart';

enum InviteRoomStatus { idle, sending, sent, failure }

final class InviteFailure extends Equatable {
  const InviteFailure(this.userId, this.type);

  final String userId;

  final RoomActionFailureType type;

  @override
  List<Object?> get props => [userId, type];
}

final class InviteRoomState extends Equatable {
  const InviteRoomState({
    this.status = InviteRoomStatus.idle,
    this.failures = const [],
  });

  final InviteRoomStatus status;

  final List<InviteFailure> failures;

  bool get sending => status == InviteRoomStatus.sending;

  @override
  List<Object?> get props => [status, failures];
}
