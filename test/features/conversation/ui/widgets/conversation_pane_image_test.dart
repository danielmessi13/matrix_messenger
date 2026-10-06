import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/core/services/image_file_picker.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/conversation/data/repositories/conversation_repository.dart';
import 'package:matrix_messenger/features/conversation/data/repositories/media_repository.dart';
import 'package:matrix_messenger/features/conversation/domain/models/conversation_failure.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/conversation_pane.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/image_message.dart';
import 'package:matrix_messenger/features/rooms/data/repositories/room_repository.dart';

import '../../../../../testing/desktop_size.dart';
import '../../../../../testing/fakes/repositories/fake_conversation_repository.dart';
import '../../../../../testing/fakes/repositories/fake_media_repository.dart';
import '../../../../../testing/fakes/repositories/fake_room_repository.dart';
import '../../../../../testing/fakes/services/fake_image_file_picker.dart';
import '../../../../../testing/models/message.dart';
import '../../../../../testing/models/room.dart';

void main() {
  late FakeConversationRepository repository;
  late FakeRoomRepository rooms;
  late FakeImageFilePicker picker;

  setUp(() {
    repository = FakeConversationRepository();
    rooms = FakeRoomRepository();
    picker = FakeImageFilePicker('/fotos/gato.png');
  });

  tearDown(() => rooms.dispose());

  const attach = Key('attach_image');

  Future<void> pumpReady(
    WidgetTester tester, {
    ConversationSnapshot? snapshot,
  }) async {
    useDesktopSize(tester);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ConversationRepository>.value(value: repository),
          RepositoryProvider<RoomRepository>.value(value: rooms),
          RepositoryProvider<MediaRepository>.value(
            value: FakeMediaRepository(),
          ),
          RepositoryProvider<ImageFilePicker>.value(value: picker),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ConversationPane(
              room: kTeamRoom,
              ownUserId: '@eu:b.c',
              now: kDay.add(const Duration(hours: 12)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    repository.conversation.snapshots.add(snapshot ?? kSnapshot);
    await tester.pump();
    await tester.pump();
  }

  IconButton attachButton(WidgetTester tester) => tester.widget<IconButton>(
    find.descendant(of: find.byKey(attach), matching: find.byType(IconButton)),
  );

  testWidgets('o + escolhe a imagem e envia o caminho', (tester) async {
    await pumpReady(tester);

    await tester.tap(find.byKey(attach));
    await tester.pump();

    expect(picker.calls, 1);
    expect(repository.conversation.sentImages, [('/fotos/gato.png', null)]);
  });

  testWidgets('cancelar a escolha não envia nada', (tester) async {
    picker.path = null;
    await pumpReady(tester);

    await tester.tap(find.byKey(attach));
    await tester.pump();

    expect(repository.conversation.sentImages, isEmpty);
  });

  testWidgets('o + fica desabilitado enquanto a imagem entra na fila', (
    tester,
  ) async {
    final gate = repository.conversation.sendImageCompleter = Completer<void>();
    await pumpReady(tester);

    await tester.tap(find.byKey(attach));
    await tester.pump();
    expect(attachButton(tester).onPressed, isNull);
    gate.complete();
    await tester.pump();

    expect(attachButton(tester).onPressed, isNotNull);
  });

  testWidgets('arquivo que não é imagem avisa', (tester) async {
    repository.conversation.sendImageResult = const Result.error(
      ConversationFailure(ConversationFailureType.invalidImage),
    );
    await pumpReady(tester);

    await tester.tap(find.byKey(attach));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('O arquivo não é uma imagem PNG, JPEG, GIF ou WebP.'),
      findsOneWidget,
    );
  });

  testWidgets('falha no envio avisa', (tester) async {
    repository.conversation.sendImageResult = const Result.error(
      ConversationFailure(ConversationFailureType.network),
    );
    await pumpReady(tester);

    await tester.tap(find.byKey(attach));
    await tester.pump();
    await tester.pump();

    expect(find.text('Não foi possível enviar a imagem.'), findsOneWidget);
  });

  testWidgets('a mensagem de imagem aparece na timeline', (tester) async {
    await pumpReady(
      tester,
      snapshot: ConversationSnapshot(
        items: [
          DateDividerItem(kDay),
          MessageItem(
            id: '\$img',
            eventId: '\$img',
            senderId: '@bob:b.c',
            senderName: 'Bob',
            isOwn: false,
            timestamp: kDay.add(const Duration(hours: 10)),
            kind: MessageKind.image,
            image: const ImageContent(
              media: 'x',
              filename: 'gato.png',
              width: 640,
              height: 480,
            ),
          ),
        ],
        reachedStart: true,
      ),
    );

    expect(find.byType(ImageMessage), findsOneWidget);
  });
}
