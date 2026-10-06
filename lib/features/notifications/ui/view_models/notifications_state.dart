import 'package:equatable/equatable.dart';

final class NotificationsState extends Equatable {
  const NotificationsState({
    this.windowFocused = true,
    this.openRoomId,
    this.tappedRoomId,
  });

  final bool windowFocused;

  final String? openRoomId;

  final String? tappedRoomId;

  NotificationsState copyWith({
    bool? windowFocused,
    String? Function()? openRoomId,
    String? Function()? tappedRoomId,
  }) => NotificationsState(
    windowFocused: windowFocused ?? this.windowFocused,
    openRoomId: openRoomId != null ? openRoomId() : this.openRoomId,
    tappedRoomId: tappedRoomId != null ? tappedRoomId() : this.tappedRoomId,
  );

  @override
  List<Object?> get props => [windowFocused, openRoomId, tappedRoomId];
}
