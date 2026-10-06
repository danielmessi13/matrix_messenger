import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/services/matrix_service.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/src/rust/api/auth.dart';
import 'package:matrix_messenger/src/rust/api/client.dart';
import 'package:matrix_messenger/src/rust/api/recovery.dart';
import 'package:matrix_messenger/src/rust/api/rooms.dart';
import 'package:matrix_messenger/src/rust/api/threads.dart';
import 'package:matrix_messenger/src/rust/api/timeline.dart';

import '../../../testing/fakes/services/fake_matrix_bridge.dart';
import '../../../testing/fakes/services/fake_matrix_client.dart';
import '../../../testing/fakes/services/fake_room_timeline.dart';
import '../../../testing/models/user_session.dart';

void main() {
  late FakeMatrixBridge bridge;
  late MatrixService service;

  setUp(() {
    bridge = FakeMatrixBridge();
    service = MatrixService(dataDir: () async => '/tmp/dados', bridge: bridge);
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  Future<Result<MatrixClient>> login() =>
      service.login(homeserver: 'matrix.org', username: 'alice', password: 'x');

  Future<Result<MatrixClient>> loginWithBrowser([void Function(Uri)? onUrl]) =>
      service.loginWithBrowser(
        homeserver: 'matrix.org',
        onAuthorizationUrl: onUrl ?? (_) {},
      );

  test('sessão revogada libera o cliente e avisa', () async {
    final client = FakeMatrixClient.of(kUserSession);
    bridge.loginClient = client;
    var revoked = 0;
    service.sessionRevoked.listen((_) => revoked++);

    await login();
    client.sessionEventsController.add(SessionEvent.revoked);
    await flush();

    expect(client.isDisposed, isTrue);
    expect(revoked, 1);
  });

  test('novo login libera o cliente anterior', () async {
    final first = FakeMatrixClient.of(kUserSession);
    bridge.loginClient = first;
    await login();

    bridge.loginClient = FakeMatrixClient.of(kUserSession);
    await login();

    expect(first.isDisposed, isTrue);
  });

  test('login pelo navegador repassa a URL, adota o cliente e descarta o '
      'OidcLogin', () async {
    final urls = <Uri>[];
    final client = FakeMatrixClient.of(kUserSession);

    final result = loginWithBrowser(urls.add);
    await flush();
    bridge.browserLogin.finish(client);

    expect(await result, isA<Ok<MatrixClient>>());
    expect(urls, [Uri.parse(bridge.browserLogin.authorizationUrl)]);
    expect(bridge.browserLogin.isDisposed, isTrue);
  });

  test('cancelar encerra o login pelo navegador com cancelled', () async {
    final result = loginWithBrowser();
    await flush();

    await service.cancelBrowserLogin();

    expect(
      await result,
      isA<Error<MatrixClient>>().having(
        (error) => (error.error as AuthError).kind,
        'kind',
        AuthErrorKind.cancelled,
      ),
    );
    expect(bridge.browserLogin.isDisposed, isTrue);
  });

  test('login por senha cancela o login pelo navegador pendente', () async {
    final pending = loginWithBrowser();
    await flush();

    await login();

    expect(bridge.browserLogin.cancelCalls, 1);
    expect(await pending, isA<Error<MatrixClient>>());
  });

  test('cancelar sem login pendente não faz nada', () async {
    await service.cancelBrowserLogin();
    expect(bridge.browserLogin.cancelCalls, 0);
  });

  test('watchRooms repassa o stream do cliente atual', () async {
    final client = FakeMatrixClient.of(kUserSession);
    bridge.loginClient = client;
    await login();
    const summary = RoomSummary(
      id: '!a:b.c',
      name: 'Sala A',
      isDirect: false,
      isInvite: false,
      isPublic: false,
      unreadMessages: 0,
      unreadMentions: 0,
      memberCount: 1,
      heroes: [],
      latest: null,
    );

    final received = service.watchRooms().first;
    client.roomsController.add([summary]);

    expect(await received, [summary]);
  });

  test('sem cliente, os streams de salas terminam vazios', () async {
    expect(await service.watchRooms().toList(), isEmpty);
    expect(await service.watchSyncStatus().toList(), isEmpty);
    expect(await service.watchRecentThreads().isEmpty, isTrue);
  });

  test(
    'watchRecentThreads repassa o stream e retry chega ao cliente',
    () async {
      final client = FakeMatrixClient.of(kUserSession);
      bridge.loginClient = client;
      await login();
      const snapshot = RecentThreadsSnapshot(
        status: RecentThreadsStatus.ready,
        threads: [],
      );

      final received = service.watchRecentThreads().first;
      client.recentThreadsController.add(snapshot);
      expect(await received, snapshot);

      await service.retryRecentThreads();
      expect(client.recentThreadsRetries, 1);
    },
  );

  test('openTimeline abre a conversa no cliente atual', () async {
    final client = FakeMatrixClient.of(kUserSession);
    final timeline = FakeRoomTimeline();
    client.openTimelineResult = timeline;
    bridge.loginClient = client;
    await login();

    final result = await service.openTimeline('!a:b.c');

    expect(result, isA<Ok<RoomTimeline>>());
    expect((result as Ok<RoomTimeline>).value, same(timeline));
    expect(client.openedRooms, ['!a:b.c']);
  });

  test('openTimeline devolve o TimelineError do Rust', () async {
    final client = FakeMatrixClient.of(kUserSession);
    client.openTimelineError = const TimelineError(
      kind: TimelineErrorKind.roomNotFound,
      message: '!x:b.c',
    );
    bridge.loginClient = client;
    await login();

    final result = await service.openTimeline('!x:b.c');

    expect(
      (result as Error<RoomTimeline>).error,
      isA<TimelineError>().having(
        (e) => e.kind,
        'kind',
        TimelineErrorKind.roomNotFound,
      ),
    );
  });

  test('openTimeline sem cliente é erro', () async {
    expect(await service.openTimeline('!a:b.c'), isA<Error<RoomTimeline>>());
  });

  test('acceptInvite e declineInvite chamam o cliente atual', () async {
    final client = FakeMatrixClient.of(kUserSession);
    bridge.loginClient = client;
    await login();

    expect(await service.acceptInvite('!a:b.c'), isA<Ok<void>>());
    expect(await service.declineInvite('!b:b.c'), isA<Ok<void>>());

    expect(client.accepted, ['!a:b.c']);
    expect(client.declined, ['!b:b.c']);
  });

  test('acceptInvite devolve o InviteError do Rust', () async {
    final client = FakeMatrixClient.of(kUserSession);
    client.inviteError = const InviteError(
      kind: InviteErrorKind.network,
      message: 'offline',
    );
    bridge.loginClient = client;
    await login();

    final result = await service.acceptInvite('!a:b.c');

    expect(
      (result as Error<void>).error,
      isA<InviteError>().having((e) => e.kind, 'kind', InviteErrorKind.network),
    );
  });

  test('responder convite sem cliente é erro', () async {
    expect(await service.acceptInvite('!a:b.c'), isA<Error<void>>());
    expect(await service.declineInvite('!a:b.c'), isA<Error<void>>());
  });

  test('ações de sala chamam o cliente atual', () async {
    final client = FakeMatrixClient.of(kUserSession)..canInviteValue = true;
    bridge.loginClient = client;
    await login();

    expect(await service.leaveRoom('!a:b.c'), isA<Ok<void>>());
    expect(
      await service.inviteUser('!b:b.c', '@ana:b.c'),
      isA<Ok<void>>(),
    );
    expect(
      await service.canInvite('!b:b.c'),
      isA<Ok<bool>>().having((r) => r.value, 'value', isTrue),
    );

    expect(client.leftRooms, ['!a:b.c']);
    expect(client.invitedUsers, [('!b:b.c', '@ana:b.c')]);
  });

  test('leaveRoom devolve o RoomActionError do Rust', () async {
    final client = FakeMatrixClient.of(kUserSession);
    client.roomActionError = const RoomActionError(
      kind: RoomActionErrorKind.forbidden,
      message: 'x',
    );
    bridge.loginClient = client;
    await login();

    final result = await service.leaveRoom('!a:b.c');

    expect(
      (result as Error<void>).error,
      isA<RoomActionError>().having(
        (e) => e.kind,
        'kind',
        RoomActionErrorKind.forbidden,
      ),
    );
  });

  test('ações de sala sem cliente são erro', () async {
    expect(await service.leaveRoom('!a:b.c'), isA<Error<void>>());
    expect(await service.inviteUser('!a:b.c', '@ana:b.c'), isA<Error<void>>());
    expect(await service.canInvite('!a:b.c'), isA<Error<bool>>());
  });

  test('recover devolve o RecoveryError do Rust', () async {
    final client = FakeMatrixClient.of(kUserSession);
    client.recoverError = const RecoveryError(
      kind: RecoveryErrorKind.invalidKey,
      message: 'MAC',
    );
    bridge.loginClient = client;
    await login();

    final result = await service.recover('errada');

    expect(client.recoveredWith, ['errada']);
    expect(
      (result as Error<void>).error,
      isA<RecoveryError>().having(
        (e) => e.kind,
        'kind',
        RecoveryErrorKind.invalidKey,
      ),
    );
  });

  test('sem cliente, recover é erro e o status termina vazio', () async {
    expect(await service.recover('EsTx'), isA<Error<void>>());
    expect(await service.watchRecovery().toList(), isEmpty);
  });

  test('repassa keepSignedIn para a ponte nos dois logins', () async {
    await service.login(
      homeserver: 'matrix.org',
      username: 'alice',
      password: 'x',
      keepSignedIn: false,
    );
    final browser = service.loginWithBrowser(
      homeserver: 'matrix.org',
      onAuthorizationUrl: (_) {},
      keepSignedIn: false,
    );
    await flush();
    bridge.browserLogin.finish(FakeMatrixClient.of(kUserSession));
    await browser;

    expect(bridge.keepSignedInCalls, [false, false]);
  });
}
