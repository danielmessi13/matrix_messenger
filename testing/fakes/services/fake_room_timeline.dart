import 'dart:async';

import 'package:matrix_messenger/src/rust/api/timeline.dart';

class FakeRoomTimeline implements RoomTimeline {
  final snapshots = StreamController<TimelineSnapshot>.broadcast();

  bool reachedStartOnPaginate = false;
  int paginateCalls = 0;
  final sentBodies = <String>[];
  final replies = <(String, String)>[];
  final retried = <String>[];
  final cancelled = <String>[];
  int markAsReadCalls = 0;
  final openedThreads = <String>[];
  RoomTimeline? thread;
  Object? error;

  @override
  bool isDisposed = false;

  @override
  Stream<TimelineSnapshot> watch() => snapshots.stream;

  @override
  Future<bool> paginateBackwards() async {
    paginateCalls++;
    _throwIfError();
    return reachedStartOnPaginate;
  }

  @override
  Future<void> sendMarkdown({required String body}) async {
    _throwIfError();
    sentBodies.add(body);
  }

  @override
  Future<void> sendReply({
    required String body,
    required String inReplyTo,
  }) async {
    _throwIfError();
    replies.add((body, inReplyTo));
  }

  @override
  Future<void> retry({required String itemId}) async => retried.add(itemId);

  @override
  Future<void> cancel({required String itemId}) async => cancelled.add(itemId);

  @override
  Future<void> markAsRead() async => markAsReadCalls++;

  @override
  Future<RoomTimeline> openThread({required String rootEventId}) async {
    openedThreads.add(rootEventId);
    _throwIfError();
    return thread ?? FakeRoomTimeline();
  }

  @override
  void dispose() {
    isDisposed = true;
    snapshots.close();
  }

  void _throwIfError() {
    if (error case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }
}
