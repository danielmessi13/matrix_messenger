import '../../../../src/rust/api/rooms.dart' as bridge;
import '../../domain/models/room.dart';

LatestMessage toLatestMessage(bridge.LatestMessage latest) => LatestMessage(
  senderName: latest.senderName,
  isOwn: latest.isOwn,
  kind: _toKind(latest.kind),
  body: latest.body,
  timestamp: DateTime.fromMillisecondsSinceEpoch(latest.timestampMs),
);

// O switch quebra se o Rust ganhar um caso novo.
LatestMessageKind _toKind(bridge.LatestMessageKind kind) => switch (kind) {
  bridge.LatestMessageKind.text => LatestMessageKind.text,
  bridge.LatestMessageKind.image => LatestMessageKind.image,
  bridge.LatestMessageKind.file => LatestMessageKind.file,
  bridge.LatestMessageKind.encrypted => LatestMessageKind.encrypted,
  bridge.LatestMessageKind.other => LatestMessageKind.other,
};
