import 'package:equatable/equatable.dart';

import '../../../domain/models/auth_failure.dart';

enum LoginStatus { idle, running, failure }

final class LoginState extends Equatable {
  const LoginState({this.status = LoginStatus.idle, this.failureType});

  final LoginStatus status;

  final AuthFailureType? failureType;

  @override
  List<Object?> get props => [status, failureType];
}
