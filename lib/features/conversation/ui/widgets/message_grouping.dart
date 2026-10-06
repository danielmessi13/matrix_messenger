import 'package:equatable/equatable.dart';

import '../../domain/models/timeline_item.dart';

const groupWindow = Duration(minutes: 5);

bool continuesGroup(TimelineItem? previous, MessageItem message) =>
    previous is MessageItem &&
    sameSenderNearby(previous, message) &&
    !_repliesToMe(previous) &&
    !_repliesToMe(message);

bool sameSenderNearby(TimelineItem? previous, MessageItem message) =>
    previous is MessageItem &&
    sameSender(previous, message) &&
    message.timestamp.difference(previous.timestamp).abs() < groupWindow;

bool sameSender(TimelineItem? previous, MessageItem message) =>
    previous is MessageItem && previous.senderId == message.senderId;

bool _repliesToMe(MessageItem message) =>
    !message.isOwn && (message.replyTo?.isOwn ?? false);

sealed class TimelineRow extends Equatable {
  const TimelineRow();

  TimelineItem get first;

  TimelineItem get last;
}

final class ItemRow extends TimelineRow {
  const ItemRow(this.item);

  final TimelineItem item;

  @override
  TimelineItem get first => item;

  @override
  TimelineItem get last => item;

  @override
  List<Object?> get props => [item];
}

final class RoomEventGroupRow extends TimelineRow {
  const RoomEventGroupRow(this.events);

  final List<RoomEventItem> events;

  String get id => events.first.id;

  @override
  RoomEventItem get first => events.first;

  @override
  RoomEventItem get last => events.last;

  @override
  List<Object?> get props => [events];
}

List<TimelineRow> groupRoomEvents(List<TimelineItem> items) {
  final rows = <TimelineRow>[];
  var run = <RoomEventItem>[];
  void flush() {
    if (run.length == 1) rows.add(ItemRow(run.single));
    if (run.length > 1) rows.add(RoomEventGroupRow(run));
    run = [];
  }

  for (final item in items) {
    if (item is RoomEventItem) {
      run.add(item);
      continue;
    }
    flush();
    rows.add(ItemRow(item));
  }
  flush();
  return rows;
}
