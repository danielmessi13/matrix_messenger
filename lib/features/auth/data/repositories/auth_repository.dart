import '../../../../core/utils/result.dart';
import '../../domain/models/auth_failure.dart';
import '../../domain/models/user_session.dart';

abstract interface class AuthRepository {
  Stream<UserSession?> get sessionChanges;

  Future<Result<UserSession?>> restoreSession();

  Future<Result<UserSession>> login({
    required String homeserver,
    required String username,
    required String password,
    bool keepSignedIn = true,
  });

  /// Motivo da última saída que o usuário não pediu (ex.: sessão revogada em outro cliente).
  AuthFailureType? get lastSignOutReason;

  Future<Result<UserSession>> loginWithBrowser({
    required String homeserver,
    required void Function(Uri url) onAuthorizationUrl,
    bool keepSignedIn = true,
  });

  Future<void> cancelBrowserLogin();

  Future<Result<void>> logout();

  Future<void> dispose();
}
