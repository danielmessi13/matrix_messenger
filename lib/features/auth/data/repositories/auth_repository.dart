import '../../../../core/utils/result.dart';
import '../../domain/models/user_session.dart';

abstract interface class AuthRepository {
  UserSession? get currentSession;

  Stream<UserSession?> get sessionChanges;

  Future<Result<UserSession?>> restoreSession();

  Future<Result<UserSession>> login({
    required String homeserver,
    required String username,
    required String password,
  });

  Future<Result<void>> logout();

  Future<void> dispose();
}
