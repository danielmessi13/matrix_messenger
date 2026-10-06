import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/services/matrix_service.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/src/rust/api/auth.dart';
import 'package:matrix_messenger/src/rust/api/recovery.dart';
import 'package:matrix_messenger/src/rust/api/rooms.dart';
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
      unreadMessages: 0,
      unreadMentions: 0,
      unreadThreadReplies: 0,
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
  });

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
}
