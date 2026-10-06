import 'package:equatable/equatable.dart';

enum InviteStatus { idle, accepting, declining, failure }

final class InviteState extends Equatable {
  const InviteState({this.status = InviteStatus.idle});

  final InviteStatus status;

  bool get isRunning =>
      status == InviteStatus.accepting || status == InviteStatus.declining;

  @override
  List<Object?> get props => [status];
}
