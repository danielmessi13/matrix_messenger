import 'package:equatable/equatable.dart';

class UserSession extends Equatable {
  const UserSession({
    required this.userId,
    required this.deviceId,
    this.sessionSaved = true,
  });

  final String userId;

  final String deviceId;

  /// `false` quando o cofre do SO estava indisponível: a sessão vale só até o app fechar.
  final bool sessionSaved;

  @override
  List<Object?> get props => [userId, deviceId, sessionSaved];
}
