import 'package:equatable/equatable.dart';

import '../../../domain/models/create_room_failure.dart';
import '../../../domain/models/new_room.dart';

enum InviteChipStatus { checking, found, unknown, invalidFormat, notFound }

final class InviteChip extends Equatable {
  const InviteChip(this.id, this.status, [this.displayName]);

  final String id;

  final InviteChipStatus status;

  final String? displayName;

  bool get isError =>
      status == InviteChipStatus.invalidFormat ||
      status == InviteChipStatus.notFound;

  bool get blocksSubmit => isError || status == InviteChipStatus.checking;

  @override
  List<Object?> get props => [id, status, displayName];
}

enum NewRoomTab { create, join }

enum NewRoomStatus { idle, creating, failure, success }

final class NewRoomState extends Equatable {
  const NewRoomState({
    this.name = '',
    this.topic = '',
    this.isPublic = false,
    this.invites = const [],
    this.query = '',
    this.tab = NewRoomTab.create,
    this.status = NewRoomStatus.idle,
    this.failure,
    this.created,
  });

  final String name;

  final String topic;

  final bool isPublic;

  final List<InviteChip> invites;

  final String query;

  final NewRoomTab tab;

  final NewRoomStatus status;

  final CreateRoomFailureType? failure;

  final CreatedRoom? created;

  bool get creating => status == NewRoomStatus.creating;

  bool get canSubmit =>
      !creating &&
      name.trim().isNotEmpty &&
      !invites.any((chip) => chip.blocksSubmit);

  List<String> get invalidFormatIds => _idsWith(InviteChipStatus.invalidFormat);

  List<String> get notFoundIds => _idsWith(InviteChipStatus.notFound);

  List<String> _idsWith(InviteChipStatus status) => [
    for (final chip in invites)
      if (chip.status == status) chip.id,
  ];

  NewRoomState copyWith({
    String? name,
    String? topic,
    bool? isPublic,
    List<InviteChip>? invites,
    String? query,
    NewRoomTab? tab,
    NewRoomStatus? status,
    CreateRoomFailureType? Function()? failure,
    CreatedRoom? Function()? created,
  }) => NewRoomState(
    name: name ?? this.name,
    topic: topic ?? this.topic,
    isPublic: isPublic ?? this.isPublic,
    invites: invites ?? this.invites,
    query: query ?? this.query,
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
    invites,
    query,
    tab,
    status,
    failure,
    created,
  ];
}
