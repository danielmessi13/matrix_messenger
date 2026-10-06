import '../../src/rust/api/client.dart';
import '../../src/rust/api/oidc.dart';

// As funções estáticas do Rust ficam aqui para o MatrixService poder ser testado sem a ponte.
class MatrixBridge {
  const MatrixBridge();

  Future<MatrixClient?> restoreSession({required String dataDir}) =>
      MatrixClient.restoreSession(dataDir: dataDir);

  Future<MatrixClient> login({
    required String homeserver,
    required String username,
    required String password,
    required String dataDir,
    required bool keepSignedIn,
  }) => MatrixClient.login(
    homeserver: homeserver,
    username: username,
    password: password,
    dataDir: dataDir,
    keepSignedIn: keepSignedIn,
  );

  Future<OidcLogin> startBrowserLogin({
    required String homeserver,
    required String dataDir,
    required bool keepSignedIn,
  }) => OidcLogin.start(
    homeserver: homeserver,
    dataDir: dataDir,
    keepSignedIn: keepSignedIn,
  );
}
