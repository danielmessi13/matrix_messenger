import '../../domain/models/timeline_item.dart';

const groupWindow = Duration(minutes: 5);

bool continuesGroup(TimelineItem? previous, MessageItem message) =>
    switch (previous) {
      MessageItem(:final senderId, :final timestamp) =>
        senderId == message.senderId &&
            message.timestamp.difference(timestamp).abs() < groupWindow &&
            !(message.replyTo?.isOwn ?? false),
      _ => false,
    };
