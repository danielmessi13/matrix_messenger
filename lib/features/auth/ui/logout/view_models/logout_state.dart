import 'package:equatable/equatable.dart';

enum LogoutStatus { idle, running, failure }

final class LogoutState extends Equatable {
  const LogoutState({this.status = LogoutStatus.idle});

  final LogoutStatus status;

  @override
  List<Object?> get props => [status];
}
