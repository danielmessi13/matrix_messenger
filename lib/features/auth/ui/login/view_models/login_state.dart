import 'package:equatable/equatable.dart';

import '../../../domain/models/auth_failure.dart';

enum LoginStatus { idle, running, awaitingBrowser, failure }

final class LoginState extends Equatable {
  const LoginState({
    this.status = LoginStatus.idle,
    this.failureType,
    this.authorizationUrl,
  });

  final LoginStatus status;

  final AuthFailureType? failureType;

  final Uri? authorizationUrl;

  @override
  List<Object?> get props => [status, failureType, authorizationUrl];
}
