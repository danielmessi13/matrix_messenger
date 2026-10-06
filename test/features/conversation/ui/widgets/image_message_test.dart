import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/conversation/data/repositories/media_repository.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/image_message.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/message_tile.dart';

import '../../../../../testing/desktop_size.dart';
import '../../../../../testing/fakes/repositories/fake_media_repository.dart';

void main() {
  late FakeMediaRepository repository;

  setUp(() => repository = FakeMediaRepository());

  const photo = ImageContent(
    media: '{"url":"mxc://b.c/gato"}',
    filename: 'gato.png',
    width: 800,
    height: 600,
    mimetype: 'image/png',
  );

  Future<void> pump(WidgetTester tester, Widget child) async {
    useDesktopSize(tester);
    await tester.pumpWidget(
      RepositoryProvider<MediaRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );
  }

  Size frameSize(WidgetTester tester) =>
      tester.getSize(find.byType(ClipRRect).first);

  test('imageBoxSize cabe em 320 mantendo a proporção', () {
    expect(imageBoxSize(800, 600), const Size(320, 240));
    expect(imageBoxSize(300, 1200), const Size(80, 320));
    expect(imageBoxSize(100, 50), const Size(100, 50));
    expect(imageBoxSize(null, 600), isNull);
    expect(imageBoxSize(0, 0), isNull);
  });

  testWidgets('placeholder enquanto carrega, depois a imagem', (tester) async {
    repository.pending = Completer<void>();
    await pump(tester, const ImageMessage(image: photo));

    expect(find.byKey(const Key('image_loading')), findsOneWidget);
    expect(frameSize(tester), const Size(320, 240));
    repository.pending!.complete();
    await tester.pump();

    expect(find.byKey(const Key('image_loading')), findsNothing);
    expect(find.byKey(const Key('image_open')), findsOneWidget);
    expect(find.bySemanticsLabel('gato.png'), findsOneWidget);
    expect(frameSize(tester), const Size(320, 240));
    expect(repository.loads, [(photo.media, true)]);
  });

  testWidgets('sem dimensões reserva um espaço fixo', (tester) async {
    repository.pending = Completer<void>();
    await pump(
      tester,
      const ImageMessage(
        image: ImageContent(media: 'x', filename: 'sem-info.jpg'),
      ),
    );

    expect(frameSize(tester), const Size(240, 180));
    repository.pending!.complete();
  });

  testWidgets('falha mostra o erro e tocar tenta de novo', (tester) async {
    repository.failure = FakeMediaRepository.networkFailure;
    await pump(tester, const ImageMessage(image: photo));
    await tester.pump();

    expect(find.byKey(const Key('image_error')), findsOneWidget);
    repository.failure = null;
    await tester.tap(find.byKey(const Key('image_error')));
    await tester.pump();

    expect(find.byKey(const Key('image_open')), findsOneWidget);
    expect(repository.loads, hasLength(2));
  });

  testWidgets('em cache não pede de novo nem mostra placeholder', (
    tester,
  ) async {
    repository.cache[(photo.media, true)] = kTinyPng;
    await pump(tester, const ImageMessage(image: photo));

    expect(find.byKey(const Key('image_open')), findsOneWidget);
    expect(repository.loads, isEmpty);
  });

  testWidgets('mostra a legenda abaixo da imagem', (tester) async {
    await pump(
      tester,
      const ImageMessage(
        image: ImageContent(
          media: 'x',
          filename: 'gato.png',
          caption: 'olha o gato',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('olha o gato'), findsOneWidget);
  });

  testWidgets('clicar abre o original em tela cheia e Esc fecha', (
    tester,
  ) async {
    await pump(tester, const ImageMessage(image: photo));
    await tester.pump();

    await tester.tap(find.byKey(const Key('image_open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('image_viewer')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(repository.loads, [(photo.media, true), (photo.media, false)]);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('image_viewer')), findsNothing);
  });

  testWidgets('o botão fecha o visualizador', (tester) async {
    await pump(tester, const ImageMessage(image: photo));
    await tester.pump();
    await tester.tap(find.byKey(const Key('image_open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('image_viewer_close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('image_viewer')), findsNothing);
  });

  testWidgets('clicar na imagem não fecha, clicar fora fecha', (tester) async {
    await pump(tester, const ImageMessage(image: photo));
    await tester.pump();
    await tester.tap(find.byKey(const Key('image_open')));
    await tester.pumpAndSettle();

    final image = find.descendant(
      of: find.byType(InteractiveViewer),
      matching: find.byType(Image),
    );
    await tester.tap(image);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('image_viewer')), findsOneWidget);

    await tester.tapAt(const Offset(40, 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('image_viewer')), findsNothing);
  });

  testWidgets('falha no original avisa no visualizador', (tester) async {
    await pump(tester, const ImageMessage(image: photo));
    await tester.pump();
    repository.failure = FakeMediaRepository.networkFailure;

    await tester.tap(find.byKey(const Key('image_open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('image_viewer_error')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('o tile de mensagem mostra a imagem no lugar do texto', (
    tester,
  ) async {
    await pump(
      tester,
      MessageTile(
        message: MessageItem(
          id: '\$img',
          senderId: '@bob:b.c',
          senderName: 'Bob',
          isOwn: false,
          timestamp: DateTime(2026, 10, 4, 10),
          kind: MessageKind.image,
          image: photo,
        ),
        onRetry: () async => true,
        onCancel: () async => true,
      ),
    );
    await tester.pump();

    expect(find.byType(ImageMessage), findsOneWidget);
    expect(find.text('Imagem'), findsNothing);
  });
}
