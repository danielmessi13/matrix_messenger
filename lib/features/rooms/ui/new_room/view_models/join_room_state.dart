import 'package:equatable/equatable.dart';

import '../../../domain/models/join_room_failure.dart';

enum JoinRoomStatus { idle, joining, failure, success }

final class JoinRoomState extends Equatable {
  const JoinRoomState({
    this.target = '',
    this.status = JoinRoomStatus.idle,
    this.failure,
    this.roomId,
  });

  final String target;

  final JoinRoomStatus status;

  final JoinRoomFailureType? failure;

  final String? roomId;

  bool get joining => status == JoinRoomStatus.joining;

  bool get canSubmit =>
      !joining && status != JoinRoomStatus.success && target.trim().isNotEmpty;

  JoinRoomState copyWith({
    String? target,
    JoinRoomStatus? status,
    JoinRoomFailureType? Function()? failure,
    String? Function()? roomId,
  }) => JoinRoomState(
    target: target ?? this.target,
    status: status ?? this.status,
    failure: failure == null ? this.failure : failure(),
    roomId: roomId == null ? this.roomId : roomId(),
  );

  @override
  List<Object?> get props => [target, status, failure, roomId];
}
