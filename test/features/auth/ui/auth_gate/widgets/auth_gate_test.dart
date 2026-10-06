import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/core/services/browser_launcher.dart';
import 'package:matrix_messenger/features/auth/data/repositories/auth_repository.dart';
import 'package:matrix_messenger/features/auth/domain/models/auth_failure.dart';
import 'package:matrix_messenger/features/auth/domain/models/user_session.dart';
import 'package:matrix_messenger/features/auth/ui/auth_gate/view_models/auth_gate_view_model.dart';
import 'package:matrix_messenger/features/auth/ui/auth_gate/widgets/auth_gate.dart';
import 'package:matrix_messenger/features/conversation/data/repositories/conversation_repository.dart';
import 'package:matrix_messenger/features/recovery/data/repositories/recovery_repository.dart';
import 'package:matrix_messenger/features/rooms/data/repositories/room_repository.dart';
import 'package:matrix_messenger/features/threads/data/repositories/recent_threads_repository.dart';

import '../../../../../../testing/desktop_size.dart';
import '../../../../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../../../../testing/fakes/repositories/fake_conversation_repository.dart';
import '../../../../../../testing/fakes/repositories/fake_recent_threads_repository.dart';
import '../../../../../../testing/fakes/repositories/fake_recovery_repository.dart';
import '../../../../../../testing/fakes/repositories/fake_room_repository.dart';
import '../../../../../../testing/fakes/services/fake_browser_launcher.dart';
import '../../../../../../testing/models/user_session.dart';

void main() {
  Future<void> pumpGate(
    WidgetTester tester,
    FakeAuthRepository repository, {
    Size size = const Size(1440, 900),
  }) async {
    useDesktopSize(tester, size);
    final roomRepository = FakeRoomRepository();
    addTearDown(repository.dispose);
    addTearDown(roomRepository.dispose);
    final recoveryRepository = FakeRecoveryRepository();
    addTearDown(recoveryRepository.dispose);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AuthRepository>.value(value: repository),
          RepositoryProvider<RoomRepository>.value(value: roomRepository),
          RepositoryProvider<RecentThreadsRepository>.value(
            value: FakeRecentThreadsRepository(),
          ),
          RepositoryProvider<RecoveryRepository>.value(
            value: recoveryRepository,
          ),
          RepositoryProvider<ConversationRepository>.value(
            value: FakeConversationRepository(),
          ),
          RepositoryProvider<BrowserLauncher>.value(
            value: FakeBrowserLauncher(),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: BlocProvider(
            create: (context) =>
                AuthGateViewModel(context.read<AuthRepository>())..init(),
            child: Builder(
              builder: (context) =>
                  AuthGate(viewModel: context.read<AuthGateViewModel>()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('sem sessão salva mostra o formulário de login', (tester) async {
    await pumpGate(tester, FakeAuthRepository());

    expect(find.byKey(const Key('login_submit')), findsOneWidget);
  });

  testWidgets('com sessão salva abre direto na tela do usuário logado', (
    tester,
  ) async {
    await pumpGate(tester, FakeAuthRepository(savedSession: kUserSession));

    expect(find.text('alice'), findsOneWidget);
    expect(find.byKey(const Key('login_submit')), findsNothing);
  });

  testWidgets('login com sucesso troca para a tela do usuário logado', (
    tester,
  ) async {
    await pumpGate(tester, FakeAuthRepository());

    await tester.enterText(find.byKey(const Key('login_username')), 'alice');
    await tester.enterText(find.byKey(const Key('login_password')), 'secret');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
  });

  testWidgets('janela estreita abre com a lista recolhida', (tester) async {
    await pumpGate(
      tester,
      FakeAuthRepository(savedSession: kUserSession),
      size: const Size(1100, 800),
    );

    expect(find.byKey(const Key('toggle_room_list')), findsOneWidget);
    expect(find.text('Caixa de entrada'), findsNothing);
  });

  testWidgets('sair volta para o formulário de login', (tester) async {
    final repository = FakeAuthRepository(savedSession: kUserSession);
    await pumpGate(tester, repository);

    await tester.tap(find.byKey(const Key('user_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logout')));
    await tester.pumpAndSettle();

    expect(repository.logoutCalls, 1);
    expect(find.byKey(const Key('login_submit')), findsOneWidget);
  });

  testWidgets('sessão nova sem passar pelo login atualiza a tela do usuário', (
    tester,
  ) async {
    const otherSession = UserSession(
      userId: '@bob:matrix.org',
      deviceId: 'DEVICE456',
    );
    final repository = FakeAuthRepository(
      savedSession: kUserSession,
      loginSession: otherSession,
    );
    await pumpGate(tester, repository);

    // Ex.: um novo login após soft logout, que cria outro device sem passar pelo logout.
    await repository.login(
      homeserver: 'matrix.org',
      username: 'bob',
      password: 'secret',
    );
    await tester.pumpAndSettle();

    expect(find.text('bob'), findsOneWidget);
    expect(find.text('alice'), findsNothing);
  });

  testWidgets('falha na restauração permite tentar de novo', (tester) async {
    final repository = FakeAuthRepository(
      savedSession: kUserSession,
      restoreFailure: const AuthFailure(AuthFailureType.storage),
    );
    await pumpGate(tester, repository);

    expect(find.text('Não foi possível abrir a sessão salva.'), findsOneWidget);
    expect(find.byKey(const Key('login_submit')), findsNothing);

    repository.restoreFailure = null;
    await tester.tap(find.byKey(const Key('restore_retry')));
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
  });

  testWidgets('falha na restauração permite ir ao login', (tester) async {
    await pumpGate(
      tester,
      FakeAuthRepository(
        restoreFailure: const AuthFailure(AuthFailureType.storage),
      ),
    );

    await tester.tap(find.byKey(const Key('restore_skip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_submit')), findsOneWidget);
  });

  testWidgets('sessão revogada volta ao login com a mensagem', (tester) async {
    final repository = FakeAuthRepository(savedSession: kUserSession);
    await pumpGate(tester, repository);

    repository.revokeSession();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_submit')), findsOneWidget);
    expect(
      find.text('Sua sessão foi encerrada. Entre novamente.'),
      findsOneWidget,
    );
  });
}
