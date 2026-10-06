import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/app.dart';
import 'package:matrix_messenger/core/services/browser_launcher.dart';
import 'package:matrix_messenger/core/services/system_notifications.dart';
import 'package:matrix_messenger/features/auth/data/repositories/auth_repository.dart';
import 'package:matrix_messenger/features/conversation/data/repositories/conversation_repository.dart';
import 'package:matrix_messenger/features/notifications/data/repositories/notification_repository.dart';
import 'package:matrix_messenger/features/recovery/data/repositories/recovery_repository.dart';
import 'package:matrix_messenger/features/rooms/data/repositories/room_repository.dart';
import 'package:matrix_messenger/features/threads/data/repositories/recent_threads_repository.dart';

import '../../testing/desktop_size.dart';
import '../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../testing/fakes/repositories/fake_conversation_repository.dart';
import '../../testing/fakes/repositories/fake_recent_threads_repository.dart';
import '../../testing/fakes/repositories/fake_notification_repository.dart';
import '../../testing/fakes/repositories/fake_recovery_repository.dart';
import '../../testing/fakes/repositories/fake_room_repository.dart';
import '../../testing/fakes/services/fake_browser_launcher.dart';
import '../../testing/fakes/services/fake_system_notifications.dart';
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
    final recoveryRepository = FakeRecoveryRepository();
    addTearDown(recoveryRepository.dispose);
    final notificationRepository = FakeNotificationRepository();
    addTearDown(notificationRepository.dispose);
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
          RepositoryProvider<NotificationRepository>.value(
            value: notificationRepository,
          ),
          RepositoryProvider<SystemNotifications>.value(
            value: FakeSystemNotifications(),
          ),
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

    expect(find.text('alice'), findsOneWidget);
  });
}
