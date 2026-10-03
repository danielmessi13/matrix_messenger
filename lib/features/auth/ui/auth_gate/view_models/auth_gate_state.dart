import 'package:equatable/equatable.dart';

import '../../../domain/models/user_session.dart';

sealed class AuthGateState extends Equatable {
  const AuthGateState();

  @override
  List<Object?> get props => [];
}

final class AuthGateRestoring extends AuthGateState {
  const AuthGateRestoring();
}

final class AuthGateUnauthenticated extends AuthGateState {
  const AuthGateUnauthenticated();
}

final class AuthGateAuthenticated extends AuthGateState {
  const AuthGateAuthenticated(this.session);

  final UserSession session;

  @override
  List<Object?> get props => [session];
}
