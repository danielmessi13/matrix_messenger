import 'package:equatable/equatable.dart';

import '../../../domain/models/room_action_failure.dart';

enum LeaveRoomStatus { idle, leaving, left, failure }

final class LeaveRoomState extends Equatable {
  const LeaveRoomState({this.status = LeaveRoomStatus.idle, this.failure});

  final LeaveRoomStatus status;

  final RoomActionFailureType? failure;

  @override
  List<Object?> get props => [status, failure];
}
