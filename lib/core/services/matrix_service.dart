import 'dart:developer';

import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/auth.dart';
import '../utils/result.dart';
import 'local_storage_exception.dart';

class MatrixService {
  MatrixService({Future<String> Function()? dataDir})
    : _dataDirProvider = dataDir ?? _appSupportDir;

  final Future<String> Function() _dataDirProvider;

  MatrixClient? _client;

  MatrixClient? get client => _client;

  Future<Result<MatrixClient?>> restoreSession() => _guard(() async {
    final client = await MatrixClient.restoreSession(dataDir: await _dataDir());
    return _client = client;
  });

  Future<Result<MatrixClient>> login({
    required String homeserver,
    required String username,
    required String password,
  }) => _guard(() async {
    final dataDir = await _dataDir();
    // Fecha o store do cliente anterior antes que o login apague os stores antigos.
    _releaseClient();
    final client = await MatrixClient.login(
      homeserver: homeserver,
      username: username,
      password: password,
      dataDir: dataDir,
    );
    return _client = client;
  });

  Future<Result<void>> logout() => _guard(() async {
    final client = _client;
    if (client == null) return;
    await client.logout();
    _releaseClient();
  });

  /// Libera o cliente Rust na hora, sem esperar o GC, para fechar os arquivos SQLite.
  void _releaseClient() {
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
    } on AuthError catch (error) {
      return Result.error(error);
    } on LocalStorageException catch (error) {
      return Result.error(error);
    } catch (error, stackTrace) {
      log(
        'Erro inesperado ao chamar o Rust',
        name: 'matrix',
        error: error,
        stackTrace: stackTrace,
      );
      return Result.error(error is Exception ? error : Exception('$error'));
    }
  }
}
