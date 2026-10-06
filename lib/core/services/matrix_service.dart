import 'dart:async';
import 'dart:developer';

import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/auth.dart';
import '../../src/rust/api/client.dart';
import '../../src/rust/api/notifications.dart';
import '../../src/rust/api/oidc.dart';
import '../../src/rust/api/recovery.dart';
import '../../src/rust/api/rooms.dart';
import '../../src/rust/api/timeline.dart';
import '../utils/result.dart';
import 'local_storage_exception.dart';
import 'matrix_bridge.dart';

class MatrixService {
  MatrixService({
    Future<String> Function()? dataDir,
    this._bridge = const MatrixBridge(),
  }) : _dataDirProvider = dataDir ?? _appSupportDir;

  final Future<String> Function() _dataDirProvider;

  final MatrixBridge _bridge;

  MatrixClient? _client;

  OidcLogin? _pendingBrowserLogin;

  StreamSubscription<SessionEvent>? _sessionEvents;

  final _sessionRevoked = StreamController<void>.broadcast();

  Stream<void> get sessionRevoked => _sessionRevoked.stream;

  Future<Result<MatrixClient?>> restoreSession() => _guard(() async {
    final dataDir = await _dataDir();
    // Dois clientes no mesmo store gravariam estados de criptografia diferentes por cima um do outro.
    _releaseClient();
    final client = await _bridge.restoreSession(dataDir: dataDir);
    return client == null ? null : _adopt(client);
  });

  Future<Result<MatrixClient>> login({
    required String homeserver,
    required String username,
    required String password,
  }) => _guard(() async {
    final dataDir = await _dataDir();
    await cancelBrowserLogin();
    // Fecha o store do cliente anterior antes que o login apague os stores antigos.
    _releaseClient();
    final client = await _bridge.login(
      homeserver: homeserver,
      username: username,
      password: password,
      dataDir: dataDir,
    );
    return _adopt(client);
  });

  Future<Result<MatrixClient>> loginWithBrowser({
    required String homeserver,
    required void Function(Uri url) onAuthorizationUrl,
  }) => _guard(() async {
    final dataDir = await _dataDir();
    await cancelBrowserLogin();
    _releaseClient();
    final login = await _bridge.startBrowserLogin(
      homeserver: homeserver,
      dataDir: dataDir,
    );
    _pendingBrowserLogin = login;
    try {
      onAuthorizationUrl(Uri.parse(login.authorizationUrl));
      return _adopt(await login.complete());
    } finally {
      if (identical(_pendingBrowserLogin, login)) _pendingBrowserLogin = null;
      login.dispose();
    }
  });

  Future<void> cancelBrowserLogin() async => _pendingBrowserLogin?.cancel();

  Stream<List<RoomSummary>> watchRooms() =>
      _client?.watchRooms() ?? const Stream.empty();

  Stream<SyncStatus> watchSyncStatus() =>
      _client?.watchSyncStatus() ?? const Stream.empty();

  Stream<RecoveryStatus> watchRecovery() =>
      _client?.watchRecovery() ?? const Stream.empty();

  Stream<RoomNotification> watchNotifications() =>
      _client?.watchNotifications() ?? const Stream.empty();

  Future<Result<void>> recover(String recoveryKey) => _guard(() async {
    final client = _client;
    if (client == null) throw StateError('Sem sessão ativa');
    await client.recover(recoveryKey: recoveryKey);
  });

  Future<Result<RoomTimeline>> openTimeline(String roomId) => _guard(() async {
    final client = _client;
    if (client == null) throw StateError('Sem sessão ativa');
    return client.openTimeline(roomId: roomId);
  });

  Future<Result<void>> acceptInvite(String roomId) => _guard(() async {
    final client = _client;
    if (client == null) throw StateError('Sem sessão ativa');
    await client.acceptInvite(roomId: roomId);
  });

  Future<Result<void>> declineInvite(String roomId) => _guard(() async {
    final client = _client;
    if (client == null) throw StateError('Sem sessão ativa');
    await client.declineInvite(roomId: roomId);
  });

  Future<Result<void>> logout() => _guard(() async {
    final client = _client;
    if (client == null) return;
    await client.logout();
    _releaseClient();
  });

  /// Libera o cliente Rust na hora, sem esperar o GC, para fechar os arquivos SQLite.
  MatrixClient _adopt(MatrixClient client) {
    _client = client;
    _sessionEvents = client.sessionEvents().listen((event) {
      if (event != SessionEvent.revoked) return;
      _releaseClient();
      _sessionRevoked.add(null);
    });
    return client;
  }

  void _releaseClient() {
    _sessionEvents?.cancel();
    _sessionEvents = null;
    _client?.dispose();
    _client = null;
  }

  Future<String> _dataDir() async {
    try {
      return await _dataDirProvider();
    } on Exception catch (error) {
      throw LocalStorageException('$error');
    }
  }

  static Future<String> _appSupportDir() async =>
      (await getApplicationSupportDirectory()).path;

  static Future<Result<T>> _guard<T>(Future<T> Function() action) async {
    try {
      return Result.ok(await action());
    } catch (error, stackTrace) {
      if (!_isExpected(error)) {
        log(
          'Erro inesperado ao chamar o Rust',
          name: 'matrix',
          error: error,
          stackTrace: stackTrace,
        );
      }
      return Result.error(error is Exception ? error : Exception('$error'));
    }
  }

  static bool _isExpected(Object error) =>
      error is AuthError ||
      error is TimelineError ||
      error is RecoveryError ||
      error is InviteError ||
      error is LocalStorageException;
}
