import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/rooms/data/repositories/room_repository.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room_action_failure.dart';
import 'package:matrix_messenger/features/rooms/ui/invite_room/widgets/invite_room_button.dart';

import '../../../../../../testing/desktop_size.dart';
import '../../../../../../testing/fakes/repositories/fake_room_repository.dart';

class _PerUserRoomRepository extends FakeRoomRepository {
  final results = <String, Result<void>>{};

  @override
  Future<Result<void>> inviteUser(String roomId, String userId) async {
    await super.inviteUser(roomId, userId);
    return results[userId] ?? const Result.ok(null);
  }
}

void main() {
  late _PerUserRoomRepository repository;

  setUp(() => repository = _PerUserRoomRepository()..canInviteValue = true);

  tearDown(() => repository.dispose());

  Future<void> pumpButton(WidgetTester tester) async {
    useDesktopSize(tester);
    await tester.pumpWidget(
      RepositoryProvider<RoomRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: InviteRoomButton(
              roomId: '!sala:b.c',
              roomName: 'Plantão',
              ownUserId: '@eu:b.co',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester) async {
    await pumpButton(tester);
    await tester.tap(find.byKey(const Key('invite_room')));
    await tester.pumpAndSettle();
  }

  Future<void> addChips(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('invite_room_field')), text);
    await tester.pumpAndSettle();
  }

  Finder dialog() => find.byKey(const Key('invite_room_dialog'));

  Finder submit() => find.byKey(const Key('invite_room_submit'));

  FilledButton submitButton(WidgetTester tester) =>
      tester.widget<FilledButton>(submit());

  testWidgets('sem permissão o botão não aparece', (tester) async {
    repository.canInviteValue = false;
    await pumpButton(tester);

    expect(repository.canInviteCalls, ['!sala:b.c']);
    expect(find.byKey(const Key('invite_room')), findsNothing);
  });

  testWidgets('com permissão aparece e abre o diálogo', (tester) async {
    await openDialog(tester);

    expect(dialog(), findsOneWidget);
    expect(find.text('Convidar para Plantão'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('invite_room_help'))).data,
      'Digite @usuario:servidor e aperte Enter.',
    );
    final field = tester.widget<TextField>(
      find.byKey(const Key('invite_room_field')),
    );
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('Convidar fica inativo sem chips', (tester) async {
    await openDialog(tester);

    expect(submitButton(tester).onPressed, isNull);
  });

  testWidgets('envia os ids e fecha', (tester) async {
    await openDialog(tester);
    await addChips(tester, '@ana:b.co @bia:b.co ');

    expect(submitButton(tester).onPressed, isNotNull);
    await tester.tap(submit());
    await tester.pumpAndSettle();

    expect(repository.invitedUsers, [
      ('!sala:b.c', '@ana:b.co'),
      ('!sala:b.c', '@bia:b.co'),
    ]);
    expect(dialog(), findsNothing);
  });

  testWidgets('Enter cria o chip sem enviar', (tester) async {
    await openDialog(tester);
    await tester.enterText(
      find.byKey(const Key('invite_room_field')),
      '@ana:b.co',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('invite_room_chip_@ana:b.co')), findsOneWidget);
    expect(repository.invitedUsers, isEmpty);
    expect(dialog(), findsOneWidget);
  });

  testWidgets('o próprio id não vira chip', (tester) async {
    await openDialog(tester);
    await addChips(tester, '@EU:b.co @ana:b.co ');

    expect(find.byKey(const Key('invite_room_chip_@EU:b.co')), findsNothing);
    expect(find.byKey(const Key('invite_room_chip_@ana:b.co')), findsOneWidget);
    expect(repository.checkedUsers, ['@ana:b.co']);
  });

  testWidgets('aparece quando o sync atualiza a sala e dá permissão', (
    tester,
  ) async {
    repository.canInviteValue = false;
    await pumpButton(tester);
    expect(find.byKey(const Key('invite_room')), findsNothing);

    repository.canInviteValue = true;
    repository.roomsController.add([
      const Room(id: '!sala:b.c', name: 'Plantão'),
    ]);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('invite_room')), findsOneWidget);
  });

  testWidgets('enquanto envia mostra spinner e não fecha', (tester) async {
    repository.inviteUserGate = Completer<void>();
    await openDialog(tester);
    await addChips(tester, '@ana:b.co ');

    await tester.tap(submit());
    await tester.pump();
    await tester.pump();

    expect(
      find.descendant(
        of: submit(),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(submitButton(tester).onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(dialog(), findsOneWidget);

    repository.inviteUserGate!.complete();
    await tester.pumpAndSettle();
    expect(dialog(), findsNothing);
  });

  testWidgets('sessão não verificada explica o histórico compartilhado', (
    tester,
  ) async {
    repository.results['@bia:b.co'] = const Result.error(
      RoomActionFailure(RoomActionFailureType.unverifiedDevice),
    );
    await openDialog(tester);
    await addChips(tester, '@bia:b.co ');

    await tester.tap(submit());
    await tester.pumpAndSettle();

    expect(
      find.text(
        '“@bia:b.co”: esta sala compartilha o histórico com convidados, e '
        'para isso esta sessão precisa estar verificada. Use sua chave de '
        'recuperação e tente de novo.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('falha parcial avisa, tira o chip enviado e tenta de novo', (
    tester,
  ) async {
    repository.results['@bia:b.co'] = const Result.error(
      RoomActionFailure(RoomActionFailureType.forbidden),
    );
    repository.results['@cid:b.co'] = const Result.error(
      RoomActionFailure(RoomActionFailureType.invalidUserId),
    );
    await openDialog(tester);
    await addChips(tester, '@ana:b.co @bia:b.co @cid:b.co ');

    await tester.tap(submit());
    await tester.pumpAndSettle();

    expect(dialog(), findsOneWidget);
    expect(find.text('Alguns convites não foram enviados'), findsOneWidget);
    expect(
      find.text('“@bia:b.co”: sem permissão\n“@cid:b.co”: ID inválido'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('invite_room_chip_@ana:b.co')), findsNothing);
    expect(find.byKey(const Key('invite_room_chip_@bia:b.co')), findsOneWidget);
    expect(find.byKey(const Key('invite_room_chip_@cid:b.co')), findsOneWidget);
    expect(
      find.descendant(of: submit(), matching: find.text('Tentar de novo')),
      findsOneWidget,
    );

    repository.results.clear();
    await tester.tap(submit());
    await tester.pumpAndSettle();

    expect(repository.invitedUsers.skip(3), [
      ('!sala:b.c', '@bia:b.co'),
      ('!sala:b.c', '@cid:b.co'),
    ]);
    expect(dialog(), findsNothing);
  });
}
