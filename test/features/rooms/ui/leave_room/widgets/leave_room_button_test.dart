import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/rooms/data/repositories/room_repository.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room_action_failure.dart';
import 'package:matrix_messenger/features/rooms/ui/leave_room/widgets/leave_room_button.dart';

import '../../../../../../testing/desktop_size.dart';
import '../../../../../../testing/fakes/repositories/fake_room_repository.dart';

void main() {
  late FakeRoomRepository repository;

  setUp(() => repository = FakeRoomRepository());

  tearDown(() => repository.dispose());

  Future<void> openDialog(WidgetTester tester) async {
    useDesktopSize(tester);
    await tester.pumpWidget(
      RepositoryProvider<RoomRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: LeaveRoomButton(roomId: '!sala:b.c', roomName: 'Plantão'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('leave_room')));
    await tester.pumpAndSettle();
  }

  Finder confirmButton() => find.byKey(const Key('leave_room_confirm'));

  testWidgets('abre a confirmação com o nome da sala', (tester) async {
    await openDialog(tester);

    expect(find.text('Sair de Plantão?'), findsOneWidget);
    expect(
      find.text(
        'Você deixa de receber mensagens desta sala. Para voltar a uma sala '
        'privada, você vai precisar de um novo convite.',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: confirmButton(), matching: find.text('Sair')),
      findsOneWidget,
    );
  });

  testWidgets('Cancelar fecha sem sair', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('leave_room_dialog')), findsNothing);
    expect(repository.leftRooms, isEmpty);
  });

  testWidgets('Sair chama o repositório e fecha no sucesso', (tester) async {
    await openDialog(tester);

    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(repository.leftRooms, ['!sala:b.c']);
    expect(find.byKey(const Key('leave_room_dialog')), findsNothing);
  });

  testWidgets('enquanto sai mostra spinner e não fecha', (tester) async {
    repository.leaveRoomGate = Completer<void>();
    await openDialog(tester);

    await tester.tap(confirmButton());
    await tester.pump();
    await tester.pump();

    expect(
      find.descendant(
        of: confirmButton(),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    expect(find.byKey(const Key('leave_room_dialog')), findsOneWidget);

    repository.leaveRoomGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('leave_room_dialog')), findsNothing);
  });

  testWidgets('falha mostra o alerta e oferece tentar de novo', (tester) async {
    repository.leaveRoomResult = const Result.error(
      RoomActionFailure(RoomActionFailureType.network),
    );
    await openDialog(tester);

    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível sair da sala'), findsOneWidget);
    expect(find.textContaining('Sem conexão'), findsOneWidget);
    expect(
      find.descendant(
        of: confirmButton(),
        matching: find.text('Tentar de novo'),
      ),
      findsOneWidget,
    );

    repository.leaveRoomResult = const Result.ok(null);
    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(repository.leftRooms, ['!sala:b.c', '!sala:b.c']);
    expect(find.byKey(const Key('leave_room_dialog')), findsNothing);
  });

  testWidgets('falha por permissão explica o motivo', (tester) async {
    repository.leaveRoomResult = const Result.error(
      RoomActionFailure(RoomActionFailureType.forbidden),
    );
    await openDialog(tester);

    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(find.textContaining('não permitiu'), findsOneWidget);
  });

  testWidgets('sync tira a sala com o diálogo aberto e ele ainda fecha', (
    tester,
  ) async {
    useDesktopSize(tester);
    final showButton = ValueNotifier(true);
    addTearDown(showButton.dispose);
    repository.leaveRoomGate = Completer<void>();
    await tester.pumpWidget(
      RepositoryProvider<RoomRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: showButton,
              builder: (_, show, _) => show
                  ? const LeaveRoomButton(
                      roomId: '!sala:b.c',
                      roomName: 'Plantão',
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('leave_room')));
    await tester.pumpAndSettle();
    await tester.tap(confirmButton());
    await tester.pump();

    showButton.value = false;
    await tester.pump();
    expect(find.byType(LeaveRoomButton), findsNothing);
    expect(find.byKey(const Key('leave_room_dialog')), findsOneWidget);

    repository.leaveRoomGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('leave_room_dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
