import 'package:equatable/equatable.dart';

import '../../../domain/models/create_room_failure.dart';
import '../../../domain/models/new_room.dart';
import '../../invite_chips/view_models/invite_chips_state.dart';

enum NewRoomTab { create, join }

enum NewRoomStatus { idle, creating, failure, success }

final class NewRoomState extends Equatable {
  const NewRoomState({
    this.name = '',
    this.topic = '',
    this.isPublic = false,
    this.shareHistory = true,
    this.tab = NewRoomTab.create,
    this.status = NewRoomStatus.idle,
    this.failure,
    this.created,
  });

  final String name;

  final String topic;

  final bool isPublic;

  final bool shareHistory;

  final NewRoomTab tab;

  final NewRoomStatus status;

  final CreateRoomFailureType? failure;

  final CreatedRoom? created;

  bool get creating => status == NewRoomStatus.creating;

  // Só os campos da sala; os convites vêm de canSubmitWith.
  bool get canSubmit => !creating && name.trim().isNotEmpty;

  bool canSubmitWith(InviteChipsState invites) =>
      canSubmit && !invites.blocksSubmit;

  NewRoomState copyWith({
    String? name,
    String? topic,
    bool? isPublic,
    bool? shareHistory,
    NewRoomTab? tab,
    NewRoomStatus? status,
    CreateRoomFailureType? Function()? failure,
    CreatedRoom? Function()? created,
  }) => NewRoomState(
    name: name ?? this.name,
    topic: topic ?? this.topic,
    isPublic: isPublic ?? this.isPublic,
    shareHistory: shareHistory ?? this.shareHistory,
    tab: tab ?? this.tab,
    status: status ?? this.status,
    failure: failure == null ? this.failure : failure(),
    created: created == null ? this.created : created(),
  );

  @override
  List<Object?> get props => [
    name,
    topic,
    isPublic,
    shareHistory,
    tab,
    status,
    failure,
    created,
  ];
}
