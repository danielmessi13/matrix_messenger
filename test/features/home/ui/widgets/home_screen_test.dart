import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/core/services/system_notifications.dart';
import 'package:matrix_messenger/core/ui/animated_pane.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/auth/data/repositories/auth_repository.dart';
import 'package:matrix_messenger/features/auth/domain/models/user_session.dart';
import 'package:matrix_messenger/features/conversation/data/repositories/conversation_repository.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/focus_flash.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/thread_panel.dart';
import 'package:matrix_messenger/features/home/ui/view_models/home_view_model.dart';
import 'package:matrix_messenger/features/home/ui/widgets/home_screen.dart';
import 'package:matrix_messenger/features/notifications/data/repositories/notification_repository.dart';
import 'package:matrix_messenger/features/notifications/domain/models/room_notification.dart';
import 'package:matrix_messenger/features/recovery/data/repositories/recovery_repository.dart';
import 'package:matrix_messenger/features/recovery/domain/models/recovery_status.dart';
import 'package:matrix_messenger/features/rooms/data/repositories/room_repository.dart';
import 'package:matrix_messenger/features/rooms/domain/models/failed_invite.dart';
import 'package:matrix_messenger/features/rooms/domain/models/message_hit.dart';
import 'package:matrix_messenger/features/rooms/domain/models/new_room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room_action_failure.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/view_models/room_list_view_model.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/widgets/room_list_pane.dart';
import 'package:matrix_messenger/features/threads/domain/models/recent_thread.dart';
import 'package:matrix_messenger/features/threads/ui/view_models/recent_threads_view_model.dart';

import '../../../../../testing/desktop_size.dart';
import '../../../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../../../testing/fakes/repositories/fake_conversation_repository.dart';
import '../../../../../testing/fakes/repositories/fake_recent_threads_repository.dart';
import '../../../../../testing/fakes/repositories/fake_notification_repository.dart';
import '../../../../../testing/fakes/repositories/fake_recovery_repository.dart';
import '../../../../../testing/fakes/repositories/fake_room_repository.dart';
import '../../../../../testing/fakes/services/fake_system_notifications.dart';
import '../../../../../testing/models/message.dart';
import '../../../../../testing/models/recent_thread.dart';
import '../../../../../testing/models/room.dart';
import '../../../../../testing/models/user_session.dart';

void main() {
  late FakeAuthRepository authRepository;
  late FakeRoomRepository roomRepository;
  late FakeRecoveryRepository recoveryRepository;
  late FakeConversationRepository conversationRepository;
  late FakeRecentThreadsRepository recentThreadsRepository;
  late FakeNotificationRepository notificationRepository;
  late FakeSystemNotifications systemNotifications;

  setUp(() {
    authRepository = FakeAuthRepository(savedSession: kUserSession);
    roomRepository = FakeRoomRepository();
    recoveryRepository = FakeRecoveryRepository();
    conversationRepository = FakeConversationRepository();
    recentThreadsRepository = FakeRecentThreadsRepository();
    notificationRepository = FakeNotificationRepository();
    systemNotifications = FakeSystemNotifications();
  });

  tearDown(() async {
    await authRepository.dispose();
    await roomRepository.dispose();
    await recoveryRepository.dispose();
    await recentThreadsRepository.dispose();
    await notificationRepository.dispose();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    UserSession session = kUserSession,
    Size size = const Size(1440, 900),
  }) async {
    useDesktopSize(tester, size);
    final viewModel = HomeViewModel(session);
    final roomListViewModel = RoomListViewModel(roomRepository)..init();
    addTearDown(viewModel.close);
    final recentThreadsViewModel = RecentThreadsViewModel(
      recentThreadsRepository,
    )..init();
    addTearDown(roomListViewModel.close);
    addTearDown(recentThreadsViewModel.close);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AuthRepository>.value(value: authRepository),
          RepositoryProvider<RoomRepository>.value(value: roomRepository),
          RepositoryProvider<RecoveryRepository>.value(
            value: recoveryRepository,
          ),
          RepositoryProvider<ConversationRepository>.value(
            value: conversationRepository,
          ),
          RepositoryProvider<NotificationRepository>.value(
            value: notificationRepository,
          ),
          RepositoryProvider<SystemNotifications>.value(
            value: systemNotifications,
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: HomeScreen(
            viewModel: viewModel,
            roomListViewModel: roomListViewModel,
            recentThreadsViewModel: recentThreadsViewModel,
            clock: () => kNow,
          ),
        ),
      ),
    );
  }

  Future<void> showRooms(WidgetTester tester, [List<Room>? rooms]) async {
    roomRepository.roomsController.add(rooms ?? kRooms);
    await tester.pump();
  }

  testWidgets('antes da primeira lista mostra esqueleto e nenhuma sala', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.byKey(const Key('room_skeleton')), findsWidgets);
    expect(find.text('Selecione uma conversa'), findsOneWidget);
  });

  testWidgets('clicar numa sala mostra o cabeçalho dela', (tester) async {
    await pumpScreen(tester);
    await showRooms(tester);

    await tester.tap(find.byKey(Key('room_${kTeamRoom.id}')));
    await tester.pump();

    expect(find.byKey(const Key('conversation_title')), findsOneWidget);
    expect(find.text('#lançamento-q4'), findsOneWidget);
    expect(find.text('Selecione uma conversa'), findsNothing);
  });

  testWidgets('filtro Diretas mostra só DMs', (tester) async {
    await pumpScreen(tester);
    await showRooms(tester);

    await tester.tap(find.byKey(const Key('filter_direct')));
    await tester.pump();

    expect(find.byKey(Key('room_${kDirectRoom.id}')), findsOneWidget);
    expect(find.byKey(Key('room_${kTeamRoom.id}')), findsNothing);
  });

  Future<void> showThreads(WidgetTester tester) async {
    await pumpScreen(tester);
    await showRooms(tester);
    recentThreadsRepository.controller.add(
      RecentThreads(status: RecentThreadsStatus.ready, threads: [kTeamThread]),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('filter_threads')));
    await tester.pumpAndSettle();
  }

  final teamThreadKey = Key(
    'thread_${kTeamThread.roomId}_${kTeamThread.rootEventId}',
  );

  testWidgets('filtro Threads troca a lista de salas pelas threads recentes', (
    tester,
  ) async {
    await showThreads(tester);

    expect(find.text('Threads recentes'), findsOneWidget);
    expect(find.byKey(Key('room_${kTeamRoom.id}')), findsNothing);

    await tester.tap(find.byKey(const Key('filter_inbox')));
    await tester.pumpAndSettle();
    expect(find.text('Threads recentes'), findsNothing);
    expect(find.byKey(Key('room_${kTeamRoom.id}')), findsOneWidget);
  });

  testWidgets('clicar numa thread abre a sala com o painel da thread', (
    tester,
  ) async {
    await showThreads(tester);

    await tester.tap(find.byKey(teamThreadKey));
    // Sem pumpAndSettle: a conversa sem snapshot mantém um indicador animando.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('#lançamento-q4'), findsWidgets);
    expect(find.byType(ThreadPanel), findsOneWidget);
  });

  testWidgets('voltar à sala por selectRoom não reabre a thread antiga', (
    tester,
  ) async {
    await showThreads(tester);
    await tester.tap(find.byKey(teamThreadKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(conversationRepository.conversation.openedThreads, [
      kTeamThread.rootEventId,
    ]);

    await tester.tap(find.byKey(const Key('filter_inbox')));
    await tester.pump(const Duration(milliseconds: 500));
    // Com a thread aberta a lista está recolhida: só os avatares.
    await tester.tap(find.byKey(Key('room_avatar_${kDirectRoom.id}')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(Key('room_avatar_${kTeamRoom.id}')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(conversationRepository.conversation.openedThreads, [
      kTeamThread.rootEventId,
    ]);
  });

  testWidgets('busca com o filtro Threads não esconde as threads', (
    tester,
  ) async {
    await showThreads(tester);

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();

    expect(find.byKey(teamThreadKey), findsOneWidget);
  });

  testWidgets('busca no servidor e o resultado abre a sala focada', (
    tester,
  ) async {
    roomRepository.searchResult = Result.ok(
      MessageSearchPage(
        hits: [
          MessageHit(
            roomId: kTeamRoom.id,
            roomName: kTeamRoom.name,
            eventId: kOtherMessage.eventId!,
            senderName: kOtherMessage.senderName,
            body: 'A integração com o gateway novo ficou pronta.',
            timestamp: kOtherMessage.timestamp,
          ),
        ],
      ),
    );
    await pumpScreen(tester);
    await showRooms(tester);

    await tester.enterText(find.byKey(const Key('room_search')), 'gateway');
    await tester.pump(kMessageSearchDebounce);
    await tester.pump();

    expect(roomRepository.searches, [('gateway', null)]);
    expect(find.byKey(Key('room_${kTeamRoom.id}')), findsNothing);
    final hit = find.byKey(Key('message_hit_${kOtherMessage.eventId}'));
    expect(hit, findsOneWidget);

    await tester.tap(hit);
    await tester.pump();
    conversationRepository.conversation.snapshots.add(kSnapshot);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('conversation_title')), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is MessageHighlight && w.flashing),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 2));
  });

  const desktopPlatforms = TargetPlatformVariant({
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.windows,
  });

  LogicalKeyboardKey platformModifier() =>
      defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;

  LogicalKeyboardKey otherModifier() =>
      defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.controlLeft
      : LogicalKeyboardKey.metaLeft;

  Future<void> createRoom(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('new_room_name')), 'Plantão');
    await tester.pump();
    await tester.tap(find.byKey(const Key('new_room_submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('botão abre o diálogo e a sala criada abre ao chegar', (
    tester,
  ) async {
    await pumpScreen(tester);
    await showRooms(tester);

    await tester.tap(find.byKey(const Key('new_room_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new_room_dialog')), findsOneWidget);

    await createRoom(tester);
    expect(find.byKey(const Key('new_room_dialog')), findsNothing);
    expect(find.text('Selecione uma conversa'), findsOneWidget);

    await showRooms(tester, [
      ...kRooms,
      const Room(id: '!nova:b.c', name: 'Plantão'),
    ]);
    await tester.pump();
    expect(find.text('#Plantão'), findsOneWidget);
    expect(find.byKey(const Key('failed_invites_banner')), findsNothing);
  });

  testWidgets('entrar pela aba abre a sala quando ela chega, sem banner', (
    tester,
  ) async {
    await pumpScreen(tester);
    await showRooms(tester);

    await tester.tap(find.byKey(const Key('new_room_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new_room_tab_join')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('join_room_target')),
      '#aberta:b.c',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('join_room_submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new_room_dialog')), findsNothing);
    expect(find.text('Selecione uma conversa'), findsOneWidget);

    await showRooms(tester, [
      ...kRooms,
      const Room(id: '!entrou:b.c', name: 'aberta', isPublic: true),
    ]);
    await tester.pump();
    expect(find.text('#aberta'), findsOneWidget);
    expect(find.byKey(const Key('copy_room_link')), findsOneWidget);
    expect(find.byKey(const Key('failed_invites_banner')), findsNothing);
  });

  testWidgets('entrar numa sala em que já se está só abre a sala', (
    tester,
  ) async {
    roomRepository.joinRoomResult = Result.ok(kTeamRoom.id);
    await pumpScreen(tester);
    await showRooms(tester);

    await tester.tap(find.byKey(const Key('new_room_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new_room_tab_join')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('join_room_target')),
      kTeamRoom.id,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('join_room_submit')));
    // A conversa aberta tem animação contínua: pumpAndSettle não termina.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('#lançamento-q4'), findsOneWidget);
    expect(find.byKey(const Key('failed_invites_banner')), findsNothing);
  });

  testWidgets('convites que falharam aparecem no banner e somem', (
    tester,
  ) async {
    roomRepository.createRoomResult = const Result.ok(
      CreatedRoom(
        roomId: '!nova:b.c',
        failedInvites: [
          FailedInvite('@joao:b.co', RoomActionFailureType.unknown),
        ],
      ),
    );
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('new_room_button')));
    await tester.pumpAndSettle();
    await createRoom(tester);

    expect(find.byKey(const Key('failed_invites_banner')), findsOneWidget);
    expect(
      find.text('Sala criada, mas alguns convites não foram enviados'),
      findsOneWidget,
    );
    expect(find.textContaining('@joao:b.co'), findsOneWidget);
    expect(find.textContaining('chave de recuperação'), findsNothing);

    await tester.tap(find.byKey(const Key('failed_invites_dismiss')));
    await tester.pump();
    expect(find.byKey(const Key('failed_invites_banner')), findsNothing);
  });

  testWidgets(
    'convite que falhou por sessão não verificada explica no banner',
    (
      tester,
    ) async {
      roomRepository.createRoomResult = const Result.ok(
        CreatedRoom(
          roomId: '!nova:b.c',
          failedInvites: [
            FailedInvite('@joao:b.co', RoomActionFailureType.unknown),
            FailedInvite('@bia:b.co', RoomActionFailureType.unverifiedDevice),
          ],
        ),
      );
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('new_room_button')));
      await tester.pumpAndSettle();
      await createRoom(tester);

      expect(find.textContaining('@joao:b.co, @bia:b.co'), findsOneWidget);
      expect(
        find.text(
          'Para convidar com o histórico compartilhado, verifique esta sessão '
          'com a chave de recuperação.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('nova criação sem falhas esconde o banner anterior', (
    tester,
  ) async {
    roomRepository.createRoomResult = const Result.ok(
      CreatedRoom(
        roomId: '!nova:b.c',
        failedInvites: [
          FailedInvite('@joao:b.co', RoomActionFailureType.unknown),
        ],
      ),
    );
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('new_room_button')));
    await tester.pumpAndSettle();
    await createRoom(tester);
    expect(find.byKey(const Key('failed_invites_banner')), findsOneWidget);

    roomRepository.createRoomResult = const Result.ok(
      CreatedRoom(roomId: '!outra:b.c', failedInvites: []),
    );
    await tester.tap(find.byKey(const Key('new_room_button')));
    await tester.pumpAndSettle();
    await createRoom(tester);

    expect(find.byKey(const Key('failed_invites_banner')), findsNothing);
  });

  testWidgets('cancelar o diálogo não muda nada', (tester) async {
    await pumpScreen(tester);
    await showRooms(tester);

    await tester.tap(find.byKey(const Key('new_room_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new_room_cancel')));
    await tester.pumpAndSettle();

    expect(roomRepository.createdRooms, isEmpty);
    expect(find.text('Selecione uma conversa'), findsOneWidget);
  });

  Future<void> pressN(WidgetTester tester, LogicalKeyboardKey modifier) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  testWidgets('o atalho da plataforma abre o diálogo', (tester) async {
    await pumpScreen(tester);

    await pressN(tester, platformModifier());

    expect(find.byKey(const Key('new_room_dialog')), findsOneWidget);
  }, variant: desktopPlatforms);

  testWidgets('o atalho da outra plataforma não abre o diálogo', (
    tester,
  ) async {
    await pumpScreen(tester);

    await pressN(tester, otherModifier());

    expect(find.byKey(const Key('new_room_dialog')), findsNothing);
  }, variant: desktopPlatforms);

  Future<void> pressK(WidgetTester tester, LogicalKeyboardKey modifier) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  bool searchFocused(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('room_search')))
      .focusNode!
      .hasFocus;

  testWidgets('o atalho da plataforma foca a busca', (tester) async {
    await pumpScreen(tester);

    await pressK(tester, platformModifier());

    expect(searchFocused(tester), isTrue);
  }, variant: desktopPlatforms);

  testWidgets('o atalho da outra plataforma não foca a busca', (tester) async {
    await pumpScreen(tester);

    await pressK(tester, otherModifier());

    expect(searchFocused(tester), isFalse);
  }, variant: desktopPlatforms);

  testWidgets('Cmd+K foca a busca depois de clicar fora dela', (tester) async {
    await pumpScreen(tester);
    await showRooms(tester);
    final search = find.byKey(const Key('room_search'));
    bool focused() => tester.widget<TextField>(search).focusNode!.hasFocus;

    await tester.tap(search);
    await tester.pump();
    expect(focused(), isTrue);

    await tester.tap(find.byKey(Key('room_${kTeamRoom.id}')));
    await tester.pump();
    expect(focused(), isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(focused(), isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('recolher rail e lista', (tester) async {
    await pumpScreen(tester);
    await showRooms(tester);

    await tester.tap(find.byKey(const Key('toggle_filters')));
    await tester.pump();
    expect(find.text('FILTROS'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toggle_room_list')));
    await tester.pump();
    expect(find.byKey(Key('room_avatar_${kTeamRoom.id}')), findsOneWidget);
  });

  testWidgets('sair pelo menu do avatar', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('user_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logout')));
    await tester.pumpAndSettle();

    expect(authRepository.logoutCalls, 1);
  });

  testWidgets('aviso de sessão não salva pode ser dispensado', (tester) async {
    await pumpScreen(
      tester,
      session: const UserSession(
        userId: '@alice:matrix.org',
        deviceId: 'DEVICE123',
        sessionSaved: false,
      ),
    );

    expect(find.byKey(const Key('session_not_saved')), findsOneWidget);
    await tester.tap(find.text('Entendi'));
    await tester.pump();
    expect(find.byKey(const Key('session_not_saved')), findsNothing);
  });

  testWidgets('nomes e prévias longas na largura mínima não estouram', (
    tester,
  ) async {
    final long = 'muito ' * 40;
    await pumpScreen(tester, size: const Size(1024, 640));
    await showRooms(tester, [
      Room(
        id: '!longa:b.c',
        name: 'sala com um nome $long',
        unreadMessages: 1234,
        memberCount: 9999,
        heroes: const ['Ana', 'Bruno', 'Carla', 'Diego', 'Elisa'],
        latest: LatestMessage(
          senderName: 'Alguém Com Nome Enorme',
          isOwn: false,
          kind: LatestMessageKind.text,
          body: long,
          timestamp: kNow,
        ),
      ),
    ]);
    await tester.tap(find.byKey(const Key('room_!longa:b.c')));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mostra o cartão de recuperação quando o backup está incompleto',
    (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.byKey(const Key('recovery_card')), findsNothing);

      recoveryRepository.statusController.add(RecoveryStatus.incomplete);
      await tester.pump();

      expect(find.byKey(const Key('recovery_card')), findsOneWidget);
    },
  );

  testWidgets('conta sem backup mostra o cartão de configurar', (
    tester,
  ) async {
    await pumpScreen(tester);

    recoveryRepository.statusController.add(RecoveryStatus.disabled);
    await tester.pump();

    expect(find.text('Proteja suas mensagens'), findsOneWidget);
  });

  testWidgets('o cartão de recuperação continua com o filtro Threads', (
    tester,
  ) async {
    await showThreads(tester);
    recoveryRepository.statusController.add(RecoveryStatus.incomplete);
    await tester.pumpAndSettle();

    expect(find.text('Threads recentes'), findsOneWidget);
    expect(find.byKey(const Key('recovery_card')), findsOneWidget);
  });

  double roomListWidth(WidgetTester tester) =>
      tester.getSize(find.byType(RoomListPane)).width;

  // Sem pumpAndSettle: a conversa tem spinner. Dois passos cobrem o atraso do ticker e a remoção de quem sai.
  Future<void> settlePanes(WidgetTester tester) async {
    await tester.pump(kPaneAnimationDuration);
    await tester.pump(kPaneAnimationDuration);
  }

  Future<void> openThread(WidgetTester tester) async {
    await tester.tap(find.byKey(Key('room_${kTeamRoom.id}')));
    await tester.pump();
    conversationRepository.conversation.snapshots.add(kSnapshot);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('thread_toggle_\$root')));
    await tester.pump();
    await tester.pump();
    await settlePanes(tester);
  }

  testWidgets('abrir a thread recolhe a lista e fechar devolve', (
    tester,
  ) async {
    await pumpScreen(tester);
    await showRooms(tester);
    expect(roomListWidth(tester), kRoomListWidth);

    await openThread(tester);
    expect(roomListWidth(tester), kRoomListCompactWidth);
    final panel = tester.getRect(find.byKey(const Key('thread_panel')));
    final timeline = tester.getRect(find.byKey(const Key('timeline_list')));
    expect(timeline.right, lessThanOrEqualTo(panel.left));

    await tester.tap(find.byKey(const Key('thread_panel_close')));
    await tester.pump();
    await tester.pump();
    await settlePanes(tester);
    expect(roomListWidth(tester), kRoomListWidth);
  });

  testWidgets('diminuir a janela com a thread aberta recolhe a lista', (
    tester,
  ) async {
    await pumpScreen(tester, size: const Size(1700, 900));
    await showRooms(tester);
    await openThread(tester);
    expect(roomListWidth(tester), kRoomListWidth);

    tester.view.physicalSize = const Size(1300, 900);
    await tester.pump();
    await settlePanes(tester);

    expect(roomListWidth(tester), kRoomListCompactWidth);
  });

  testWidgets(
    'abrir a lista à mão com a thread aberta deixa a thread por cima',
    (
      tester,
    ) async {
      await pumpScreen(tester);
      await showRooms(tester);
      await openThread(tester);

      await tester.tap(find.byKey(const Key('toggle_room_list')));
      await tester.pump();
      await settlePanes(tester);

      expect(roomListWidth(tester), kRoomListWidth);
      expect(find.byKey(const Key('thread_panel')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('trocar de sala com a thread aberta devolve a lista', (
    tester,
  ) async {
    await pumpScreen(tester);
    await showRooms(tester);
    await openThread(tester);
    expect(roomListWidth(tester), kRoomListCompactWidth);

    final other = kRooms.firstWhere(
      (room) => room.id != kTeamRoom.id && !room.isInvite,
    );
    await tester.tap(find.byKey(Key('room_avatar_${other.id}')));
    await tester.pump();
    await tester.pump();
    await settlePanes(tester);

    expect(roomListWidth(tester), kRoomListWidth);
  });

  testWidgets('lista aberta à mão recolhe de novo se a janela diminuir', (
    tester,
  ) async {
    await pumpScreen(tester);
    await showRooms(tester);
    await openThread(tester);
    await tester.tap(find.byKey(const Key('toggle_room_list')));
    await tester.pump();
    await settlePanes(tester);
    expect(roomListWidth(tester), kRoomListWidth);

    tester.view.physicalSize = const Size(1300, 900);
    await tester.pump();
    await settlePanes(tester);
    expect(roomListWidth(tester), kRoomListCompactWidth);

    await tester.tap(find.byKey(const Key('toggle_room_list')));
    await tester.pump();
    await settlePanes(tester);
    expect(roomListWidth(tester), kRoomListWidth);
  });

  group('notificações', () {
    testWidgets('clicar seleciona a sala', (tester) async {
      await pumpScreen(tester);
      await showRooms(tester);

      systemNotifications.tap(kTeamRoom.id);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('conversation_title')), findsOneWidget);
      expect(find.text('#lançamento-q4'), findsOneWidget);
    });

    testWidgets(
      'clicar numa sala que saiu da lista não quebra e o próximo clique funciona',
      (tester) async {
        await pumpScreen(tester);
        await showRooms(tester);

        systemNotifications.tap('!saiu:matrix.org');
        await tester.pump();
        expect(find.text('Selecione uma conversa'), findsOneWidget);

        systemNotifications.tap(kTeamRoom.id);
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('conversation_title')), findsOneWidget);
        expect(find.text('#lançamento-q4'), findsWidgets);
      },
    );

    testWidgets('não notifica a sala aberta, notifica as outras', (
      tester,
    ) async {
      await pumpScreen(tester);
      await showRooms(tester);
      await tester.tap(find.byKey(Key('room_${kDirectRoom.id}')));
      await tester.pump();

      RoomNotification from(Room room) => RoomNotification(
        roomId: room.id,
        roomName: room.name,
        isDirect: room.isDirect,
        senderName: 'Ana Ribeiro',
        body: 'oi',
        timestamp: kNow,
      );
      notificationRepository.notificationsController
        ..add(from(kDirectRoom))
        ..add(from(kTeamRoom));
      await tester.pump();

      expect(systemNotifications.shown.map((item) => item.roomId), [
        kTeamRoom.id,
      ]);
    });
  });
}
