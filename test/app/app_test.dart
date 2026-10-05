import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/app.dart';
import 'package:matrix_messenger/core/services/browser_launcher.dart';
import 'package:matrix_messenger/features/auth/data/repositories/auth_repository.dart';
import 'package:matrix_messenger/features/rooms/data/repositories/room_repository.dart';

import '../../testing/desktop_size.dart';
import '../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../testing/fakes/repositories/fake_room_repository.dart';
import '../../testing/fakes/services/fake_browser_launcher.dart';
import '../../testing/models/user_session.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester,
    FakeAuthRepository repository,
  ) async {
    useDesktopSize(tester);
    final roomRepository = FakeRoomRepository();
    addTearDown(repository.dispose);
    addTearDown(roomRepository.dispose);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AuthRepository>.value(value: repository),
          RepositoryProvider<RoomRepository>.value(value: roomRepository),
          RepositoryProvider<BrowserLauncher>.value(
            value: FakeBrowserLauncher(),
          ),
        ],
        child: const MessengerApp(),
      ),
    );
    await tester.pump();
  }

  testWidgets('sem sessão salva abre no login', (tester) async {
    await pumpApp(tester, FakeAuthRepository());

    expect(find.byKey(const Key('login_submit')), findsOneWidget);
  });

  testWidgets('com sessão salva abre na tela do usuário logado', (
    tester,
  ) async {
    await pumpApp(tester, FakeAuthRepository(savedSession: kUserSession));

    expect(find.byTooltip('@alice:matrix.org'), findsOneWidget);
  });
}
