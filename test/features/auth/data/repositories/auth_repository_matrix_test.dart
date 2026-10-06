import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/services/local_storage_exception.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/auth/data/repositories/auth_repository_matrix.dart';
import 'package:matrix_messenger/features/auth/domain/models/auth_failure.dart';
import 'package:matrix_messenger/features/auth/domain/models/user_session.dart';
import 'package:matrix_messenger/src/rust/api/auth.dart';

import '../../../../../testing/fakes/services/fake_matrix_client.dart';
import '../../../../../testing/fakes/services/fake_matrix_service.dart';
import '../../../../../testing/models/user_session.dart';

void main() {
  late FakeMatrixService service;
  late AuthRepositoryMatrix repository;
  late List<UserSession?> emitted;

  setUp(() {
    service = FakeMatrixService();
    repository = AuthRepositoryMatrix(service);
    emitted = [];
    repository.sessionChanges.listen(emitted.add);
  });

  tearDown(() async {
    await repository.dispose();
    await service.dispose();
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  Matcher isFailure(AuthFailureType type) => isA<Error<Object?>>().having(
    (result) => result.error,
    'error',
    isA<AuthFailure>().having((failure) => failure.type, 'type', type),
  );

  Future<Result<UserSession>> login() => repository.login(
    homeserver: 'matrix.org',
    username: 'alice',
    password: 'secret',
  );

  Future<Result<UserSession>> loginWithBrowser([void Function(Uri)? onUrl]) =>
      repository.loginWithBrowser(
        homeserver: 'matrix.org',
        onAuthorizationUrl: onUrl ?? (_) {},
      );

  group('loginWithBrowser', () {
    test('repassa o servidor e a URL, atualiza a sessão e emite', () async {
      final urls = <Uri>[];

      final result = await loginWithBrowser(urls.add);
      await flush();

      expect(result, isA<Ok<UserSession>>());
      expect(service.loginWithBrowserCalls, ['matrix.org']);
      expect(urls, [service.authorizationUrl]);
      expect(emitted, [kUserSession]);
    });

    test('com erro devolve a falha e não emite', () async {
      service.loginWithBrowserResult = const Result.error(
        AuthError(kind: AuthErrorKind.authorizationDenied, message: 'negado'),
      );

      final result = await loginWithBrowser();
      await flush();

      expect(result, isFailure(AuthFailureType.authorizationDenied));
      expect(emitted, isEmpty);
    });

    test('cancelBrowserLogin repassa ao service', () async {
      await repository.cancelBrowserLogin();
      expect(service.cancelBrowserLoginCalls, 1);
    });
  });

  group('sessão revogada', () {
    setUp(() async {
      await login();
      await flush();
      emitted.clear();
    });

    test('emite null e guarda o motivo', () async {
      service.revokedController.add(null);
      await flush();

      expect(emitted, [null]);
      expect(repository.lastSignOutReason, AuthFailureType.sessionRevoked);
    });

    test('novo login limpa o motivo', () async {
      service.revokedController.add(null);
      await flush();

      await login();

      expect(repository.lastSignOutReason, isNull);
    });

    test(
      'logout manual depois de um novo login não traz o motivo de volta',
      () async {
        service.revokedController.add(null);
        await flush();
        await loginWithBrowser();

        await repository.logout();

        expect(repository.lastSignOutReason, isNull);
      },
    );
  });

  group('restoreSession', () {
    test('com sessão salva atualiza a sessão e emite', () async {
      service.restoreResult = Result.ok(FakeMatrixClient.of(kUserSession));

      final result = await repository.restoreSession();
      await flush();

      expect(result, isA<Ok<UserSession?>>());
      expect(emitted, [kUserSession]);
    });

    test('sem sessão salva continua sem sessão', () async {
      final result = await repository.restoreSession();
      await flush();

      expect(result, isA<Ok<UserSession?>>());
      expect(emitted, [null]);
    });

    test('com erro devolve a falha e não emite', () async {
      service.restoreResult = const Result.error(
        AuthError(kind: AuthErrorKind.storage, message: 'cofre bloqueado'),
      );

      final result = await repository.restoreSession();
      await flush();

      expect(result, isFailure(AuthFailureType.storage));
      expect(emitted, isEmpty);
    });
  });

  group('login', () {
    test('com sucesso atualiza a sessão e emite', () async {
      final result = await login();
      await flush();

      expect(result, isA<Ok<UserSession>>());
      expect(emitted, [kUserSession]);
    });

    test('sem cofre do sistema, a sessão vem marcada como não salva', () async {
      service.loginResult = Result.ok(
        FakeMatrixClient(
          userId: kUserSession.userId,
          deviceId: kUserSession.deviceId,
          sessionSaved: false,
        ),
      );

      final result = await login();

      expect(
        result,
        isA<Ok<UserSession>>().having(
          (ok) => ok.value.sessionSaved,
          'sessionSaved',
          isFalse,
        ),
      );
    });

    test('sem "Manter conectado" não salvar é o esperado, sem aviso', () async {
      service.loginResult = Result.ok(
        FakeMatrixClient(
          userId: kUserSession.userId,
          deviceId: kUserSession.deviceId,
          sessionSaved: false,
        ),
      );

      final result = await repository.login(
        homeserver: 'matrix.org',
        username: 'alice',
        password: 'secret',
        keepSignedIn: false,
      );

      expect(service.keepSignedInCalls, [false]);
      expect(
        result,
        isA<Ok<UserSession>>().having(
          (ok) => ok.value.sessionSaved,
          'sessionSaved',
          isTrue,
        ),
      );
    });

    test('repassa os dados ao service', () async {
      await repository.login(
        homeserver: 'example.org',
        username: 'bob',
        password: 'pw',
      );

      expect(service.loginCalls.single, (
        homeserver: 'example.org',
        username: 'bob',
        password: 'pw',
      ));
    });

    test('com erro devolve a falha e mantém a sessão', () async {
      service.loginResult = const Result.error(
        AuthError(kind: AuthErrorKind.invalidCredentials, message: '403'),
      );

      final result = await login();
      await flush();

      expect(result, isFailure(AuthFailureType.invalidCredentials));
      expect(emitted, isEmpty);
    });
  });

  group('logout', () {
    test('com sucesso limpa a sessão e emite null', () async {
      await login();

      final result = await repository.logout();
      await flush();

      expect(result, isA<Ok<void>>());
      expect(emitted, [kUserSession, null]);
    });

    test('com erro devolve a falha e mantém a sessão', () async {
      await login();
      service.logoutResult = const Result.error(
        AuthError(kind: AuthErrorKind.homeserverUnreachable, message: 'dns'),
      );

      final result = await repository.logout();
      await flush();

      expect(result, isFailure(AuthFailureType.homeserverUnreachable));
      expect(emitted, [kUserSession]);
    });
  });

  test('operação concluída depois do dispose não gera erro', () async {
    await repository.dispose();

    await expectLater(login(), completes);
  });

  test('login devolve a sessão com o usuário e o device do cliente', () async {
    service.loginResult = Result.ok(
      FakeMatrixClient(userId: '@bob:example.org', deviceId: 'BOBDEVICE'),
    );

    final result = await login();

    expect(
      result,
      isA<Ok<UserSession>>().having(
        (ok) => ok.value,
        'value',
        const UserSession(userId: '@bob:example.org', deviceId: 'BOBDEVICE'),
      ),
    );
  });

  group('tradução dos erros do service', () {
    const expectedTypes = {
      AuthErrorKind.invalidHomeserver: AuthFailureType.invalidHomeserver,
      AuthErrorKind.homeserverUnreachable:
          AuthFailureType.homeserverUnreachable,
      AuthErrorKind.invalidCredentials: AuthFailureType.invalidCredentials,
      AuthErrorKind.userDeactivated: AuthFailureType.userDeactivated,
      AuthErrorKind.rateLimited: AuthFailureType.rateLimited,
      AuthErrorKind.storage: AuthFailureType.storage,
      AuthErrorKind.oidcNotSupported: AuthFailureType.oidcNotSupported,
      AuthErrorKind.authorizationDenied: AuthFailureType.authorizationDenied,
      AuthErrorKind.timedOut: AuthFailureType.timedOut,
      AuthErrorKind.cancelled: AuthFailureType.cancelled,
      AuthErrorKind.unknown: AuthFailureType.unknown,
    };

    test('cobre todos os tipos de erro do Rust', () {
      expect(expectedTypes.keys, unorderedEquals(AuthErrorKind.values));
    });

    for (final MapEntry(key: kind, value: type) in expectedTypes.entries) {
      test(
        'AuthErrorKind.${kind.name} vira AuthFailureType.${type.name}',
        () async {
          service.loginResult = Result.error(
            AuthError(kind: kind, message: 'detalhe'),
          );

          expect(await login(), isFailure(type));
        },
      );
    }

    test('falha na pasta de dados vira storage', () async {
      service.loginResult = const Result.error(
        LocalStorageException('sem permissão'),
      );

      expect(await login(), isFailure(AuthFailureType.storage));
    });

    test('outro erro vira unknown', () async {
      service.loginResult = Result.error(Exception('boom'));

      expect(await login(), isFailure(AuthFailureType.unknown));
    });

    test('o detalhe técnico do Rust é preservado para log', () async {
      service.loginResult = const Result.error(
        AuthError(kind: AuthErrorKind.unknown, message: 'M_UNKNOWN: falhou'),
      );

      expect(
        await login(),
        isA<Error<UserSession>>().having(
          (error) => (error.error as AuthFailure).details,
          'details',
          'M_UNKNOWN: falhou',
        ),
      );
    });
  });
}
