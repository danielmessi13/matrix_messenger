import 'package:equatable/equatable.dart';

sealed class UserCheck extends Equatable {
  const UserCheck();

  @override
  List<Object?> get props => [];
}

final class UserFound extends UserCheck {
  const UserFound([this.displayName]);

  final String? displayName;

  @override
  List<Object?> get props => [displayName];
}

final class UserNotFound extends UserCheck {
  const UserNotFound();
}

// Servidor restringe a consulta de perfil (403) ou não respondeu.
final class UserUnknown extends UserCheck {
  const UserUnknown();
}
