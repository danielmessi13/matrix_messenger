import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/auth/data/repositories/auth_repository.dart';
import 'package:matrix_messenger/features/auth/domain/models/user_session.dart';
import 'package:matrix_messenger/features/conversation/data/repositories/conversation_repository.dart';
import 'package:matrix_messenger/features/home/ui/view_models/home_view_model.dart';
import 'package:matrix_messenger/features/home/ui/widgets/home_screen.dart';
import 'package:matrix_messenger/features/recovery/data/repositories/recovery_repository.dart';
import 'package:matrix_messenger/features/recovery/domain/models/recovery_status.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/view_models/room_list_view_model.dart';

import '../../../../../testing/desktop_size.dart';
import '../../../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../../../testing/fakes/repositories/fake_conversation_repository.dart';
import '../../../../../testing/fakes/repositories/fake_recovery_repository.dart';
import '../../../../../testing/fakes/repositories/fake_room_repository.dart';
import '../../../../../testing/models/room.dart';
import '../../../../../testing/models/user_session.dart';

void main() {
  late FakeAuthRepository authRepository;
  late FakeRoomRepository roomRepository;
  late FakeRecoveryRepository recoveryRepository;

  setUp(() {
    authRepository = FakeAuthRepository(savedSession: kUserSession);
    roomRepository = FakeRoomRepository();
    recoveryRepository = FakeRecoveryRepository();
  });

  tearDown(() async {
    await authRepository.dispose();
    await roomRepository.dispose();
    await recoveryRepository.dispose();
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
    addTearDown(roomListViewModel.close);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AuthRepository>.value(value: authRepository),
          RepositoryProvider<RecoveryRepository>.value(
            value: recoveryRepository,
          ),
          RepositoryProvider<ConversationRepository>.value(
            value: FakeConversationRepository(),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: HomeScreen(
            viewModel: viewModel,
            roomListViewModel: roomListViewModel,
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

  testWidgets('busca filtra pelo nome', (tester) async {
    await pumpScreen(tester);
    await showRooms(tester);

    await tester.enterText(find.byKey(const Key('room_search')), 'design');
    await tester.pump();

    expect(find.byKey(Key('room_${kQuietRoom.id}')), findsOneWidget);
    expect(find.byKey(Key('room_${kTeamRoom.id}')), findsNothing);
    expect(find.text('Resultados'), findsOneWidget);
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
    'mostra o banner de recuperação quando o backup está incompleto',
    (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.byKey(const Key('recovery_banner')), findsNothing);

      recoveryRepository.statusController.add(RecoveryStatus.incomplete);
      await tester.pump();

      expect(find.byKey(const Key('recovery_banner')), findsOneWidget);
    },
  );
}
