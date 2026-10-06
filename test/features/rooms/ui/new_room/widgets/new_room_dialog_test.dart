import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/rooms/domain/models/create_room_failure.dart';
import 'package:matrix_messenger/features/rooms/domain/models/join_room_failure.dart';
import 'package:matrix_messenger/features/rooms/domain/models/new_room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/user_check.dart';
import 'package:matrix_messenger/features/rooms/ui/new_room/view_models/join_room_view_model.dart';
import 'package:matrix_messenger/features/rooms/ui/new_room/view_models/new_room_view_model.dart';
import 'package:matrix_messenger/features/rooms/ui/new_room/widgets/new_room_dialog.dart';

import '../../../../../../testing/desktop_size.dart';
import '../../../../../../testing/fakes/repositories/fake_room_repository.dart';

void main() {
  late FakeRoomRepository repository;
  NewRoomResult? popped;
  var closed = false;

  setUp(() {
    repository = FakeRoomRepository();
    popped = null;
    closed = false;
  });

  tearDown(() => repository.dispose());

  Future<void> open(
    WidgetTester tester, [
    Size size = const Size(1440, 900),
  ]) async {
    useDesktopSize(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                popped = await showDialog<NewRoomResult>(
                  context: context,
                  builder: (_) => MultiBlocProvider(
                    providers: [
                      BlocProvider(
                        create: (_) => NewRoomViewModel(repository),
                      ),
                      BlocProvider(
                        create: (_) => JoinRoomViewModel(repository),
                      ),
                    ],
                    child: const NewRoomDialog(),
                  ),
                );
                closed = true;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  bool submitEnabled(WidgetTester tester) =>
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('new_room_submit')))
          .onPressed !=
      null;

  bool nameFocused(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('new_room_name')))
      .focusNode!
      .hasFocus;

  double submitOpacity(WidgetTester tester) => tester
      .widget<Opacity>(
        find
            .ancestor(
              of: find.byKey(const Key('new_room_submit')),
              matching: find.byType(Opacity),
            )
            .first,
      )
      .opacity;

  testWidgets('inicial: foco no nome, privada, Criar desabilitado', (
    tester,
  ) async {
    await open(tester);

    expect(find.byKey(const Key('new_room_dialog')), findsOneWidget);
    expect(find.text('Nova sala'), findsOneWidget);
    expect(find.text('Só por convite · cifrada'), findsOneWidget);
    expect(
      find.text(
        'Convidar (opcional): digite @usuario:servidor e aperte Enter.',
      ),
      findsOneWidget,
    );
    final name = tester.widget<TextField>(
      find.byKey(const Key('new_room_name')),
    );
    expect(name.focusNode!.hasFocus, isTrue);
    expect(submitEnabled(tester), isFalse);
  });

  testWidgets('trocar para pública muda a ajuda', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(const Key('new_room_public')));
    await tester.pump();

    expect(find.text('Entra quem tiver o link · sem cifra'), findsOneWidget);
  });

  testWidgets('Enter no convite cria chip e limpa o campo', (tester) async {
    await open(tester);

    await tester.enterText(
      find.byKey(const Key('new_room_invite')),
      '@ana:b.co',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.byKey(const Key('new_room_chip_@ana:b.co')), findsOneWidget);
    final invite = tester.widget<TextField>(
      find.byKey(const Key('new_room_invite')),
    );
    expect(invite.controller!.text, isEmpty);
  });

  testWidgets('chip inválido fica vermelho, explica e bloqueia', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('new_room_name')), 'Plantão');

    await tester.enterText(
      find.byKey(const Key('new_room_invite')),
      'joao@prosa,',
    );
    await tester.pump();

    expect(find.byKey(const Key('new_room_chip_joao@prosa')), findsOneWidget);
    expect(
      find.text('“joao@prosa” não está no formato @usuario:servidor.'),
      findsOneWidget,
    );
    expect(submitEnabled(tester), isFalse);

    await tester.tap(find.byKey(const Key('new_room_chip_remove_joao@prosa')));
    await tester.pump();
    expect(submitEnabled(tester), isTrue);
  });

  testWidgets('usuários inexistentes aparecem na ajuda', (tester) async {
    repository.userChecks['@joao:b.co'] = const UserNotFound();
    repository.userChecks['@rui:b.co'] = const UserNotFound();
    await open(tester);

    await tester.enterText(
      find.byKey(const Key('new_room_invite')),
      '@joao:b.co,',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('new_room_invite')),
      '@rui:b.co,',
    );
    await tester.pump();

    expect(
      find.text('“@joao:b.co”, “@rui:b.co” não existem no servidor.'),
      findsOneWidget,
    );
  });

  testWidgets('Backspace com o campo vazio remove o último chip', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.byKey(const Key('new_room_invite')),
      '@ana:b.co,',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('new_room_invite')));
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(find.byKey(const Key('new_room_chip_@ana:b.co')), findsNothing);
  });

  testWidgets('criando: campos desabilitados e nada fecha', (tester) async {
    repository.createRoomGate = Completer<void>();
    await open(tester);
    await tester.enterText(find.byKey(const Key('new_room_name')), 'Plantão');
    await tester.pump();

    await tester.tap(find.byKey(const Key('new_room_submit')));
    await tester.pump();

    expect(find.text('Criando…'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('new_room_name'))).enabled,
      isFalse,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.tap(
      find.byKey(const Key('new_room_cancel')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const Key('new_room_esc')),
      warnIfMissed: false,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(find.byKey(const Key('new_room_dialog')), findsOneWidget);

    repository.createRoomGate!.complete();
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('falha de rede mostra o alerta e Tentar de novo', (tester) async {
    repository.createRoomResult = const Result.error(
      CreateRoomFailure(CreateRoomFailureType.network),
    );
    await open(tester);
    await tester.enterText(find.byKey(const Key('new_room_name')), 'Plantão');
    await tester.pump();

    await tester.tap(find.byKey(const Key('new_room_submit')));
    await tester.pump();

    expect(find.byKey(const Key('new_room_error')), findsOneWidget);
    expect(find.text('Não foi possível criar a sala'), findsOneWidget);
    expect(
      find.text('Sem conexão com o servidor. Seus dados continuam aqui.'),
      findsOneWidget,
    );
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('falha desconhecida tem outro texto', (tester) async {
    repository.createRoomResult = const Result.error(
      CreateRoomFailure(CreateRoomFailureType.unknown),
    );
    await open(tester);
    await tester.enterText(find.byKey(const Key('new_room_name')), 'Plantão');
    await tester.pump();

    await tester.tap(find.byKey(const Key('new_room_submit')));
    await tester.pump();

    expect(find.text('Erro inesperado. Tente de novo.'), findsOneWidget);
  });

  testWidgets('depois da falha, Esc fecha', (tester) async {
    repository.createRoomResult = const Result.error(
      CreateRoomFailure(CreateRoomFailureType.network),
    );
    await open(tester);
    await tester.enterText(find.byKey(const Key('new_room_name')), 'Plantão');
    await tester.tap(find.byKey(const Key('new_room_submit')));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new_room_dialog')), findsNothing);
    expect(popped, isNull);
  });

  testWidgets('Enter no nome cria e devolve a sala', (tester) async {
    repository.createRoomResult = const Result.ok(
      CreatedRoom(roomId: '!x:b.c', failedInvites: ['@joao:b.co']),
    );
    await open(tester);

    await tester.enterText(find.byKey(const Key('new_room_name')), 'Plantão');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new_room_dialog')), findsNothing);
    expect(
      popped,
      const CreatedRoom(roomId: '!x:b.c', failedInvites: ['@joao:b.co']),
    );
  });

  testWidgets('Cancelar e o selo Esc fecham sem sala', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('new_room_cancel')));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(popped, isNull);

    closed = false;
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new_room_esc')));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('Enter no nome vazio mantém o foco no nome', (tester) async {
    await open(tester);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(nameFocused(tester), isTrue);
    expect(find.byKey(const Key('new_room_dialog')), findsOneWidget);
  });

  testWidgets('depois da falha o foco volta para o nome', (tester) async {
    repository.createRoomResult = const Result.error(
      CreateRoomFailure(CreateRoomFailureType.network),
    );
    await open(tester);
    repository.createRoomGate = Completer<void>();
    await tester.enterText(find.byKey(const Key('new_room_name')), 'Plantão');
    await tester.pump();
    await tester.tap(find.byKey(const Key('new_room_submit')));
    await tester.pump();
    expect(nameFocused(tester), isFalse);

    repository.createRoomGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new_room_error')), findsOneWidget);
    expect(nameFocused(tester), isTrue);
  });

  testWidgets('ID longo é cortado no chip e inteiro no tooltip', (
    tester,
  ) async {
    final longId = '@${'a' * 240}:example.org';
    await open(tester);

    await tester.enterText(
      find.byKey(const Key('new_room_invite')),
      '$longId,',
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final chip = find.byKey(Key('new_room_chip_$longId'));
    expect(chip, findsOneWidget);
    expect(
      tester.getSize(chip).width,
      lessThanOrEqualTo(
        tester.getSize(find.byKey(const Key('new_room_dialog'))).width,
      ),
    );
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: chip, matching: find.byType(Tooltip)).first,
    );
    expect(tooltip.message, startsWith(longId));
  });

  testWidgets('janela baixa: muitos chips e o alerta rolam sem estourar', (
    tester,
  ) async {
    repository.createRoomResult = const Result.error(
      CreateRoomFailure(CreateRoomFailureType.network),
    );
    await open(tester, const Size(1024, 500));
    await tester.enterText(find.byKey(const Key('new_room_name')), 'Plantão');
    for (var i = 0; i < 12; i++) {
      await tester.enterText(
        find.byKey(const Key('new_room_invite')),
        '@usuario$i:example.org,',
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new_room_submit')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('new_room_error')), findsOneWidget);
    expect(find.byKey(const Key('new_room_submit')).hitTestable(), findsOne);
    await tester.scrollUntilVisible(
      find.byKey(const Key('new_room_error')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('new_room_error')).hitTestable(), findsOne);
  });

  testWidgets('Criar desabilitado fica todo a 0,45; criando, inteiro', (
    tester,
  ) async {
    repository.createRoomGate = Completer<void>();
    await open(tester);
    expect(submitOpacity(tester), 0.45);

    await tester.enterText(find.byKey(const Key('new_room_name')), 'Plantão');
    await tester.pump();
    expect(submitOpacity(tester), 1);

    await tester.tap(find.byKey(const Key('new_room_submit')));
    await tester.pump();
    expect(submitEnabled(tester), isFalse);
    expect(submitOpacity(tester), 1);

    repository.createRoomGate!.complete();
    await tester.pumpAndSettle();
  });

  Future<void> openJoinTab(WidgetTester tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('new_room_tab_join')));
    await tester.pump();
  }

  TextField targetField(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(const Key('join_room_target')));

  bool joinEnabled(WidgetTester tester) =>
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('join_room_submit')))
          .onPressed !=
      null;

  testWidgets('abre em Criar; a aba Entrar troca o corpo e foca o campo', (
    tester,
  ) async {
    await open(tester);
    expect(find.byKey(const Key('new_room_name')), findsOneWidget);
    expect(find.byKey(const Key('join_room_target')), findsNothing);

    await tester.tap(find.byKey(const Key('new_room_tab_join')));
    await tester.pump();

    expect(find.byKey(const Key('new_room_name')), findsNothing);
    expect(targetField(tester).focusNode!.hasFocus, isTrue);
    expect(
      find.text('Cole um link matrix.to, um ID (!…) ou um endereço (#…).'),
      findsOneWidget,
    );
    expect(joinEnabled(tester), isFalse);
  });

  testWidgets('trocar de aba mantém o que foi digitado', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('new_room_name')), 'Plantão');
    await tester.tap(find.byKey(const Key('new_room_tab_join')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('join_room_target')),
      '#sala:b.c',
    );

    await tester.tap(find.byKey(const Key('new_room_tab_create')));
    await tester.pump();
    expect(find.text('Plantão'), findsOneWidget);

    await tester.tap(find.byKey(const Key('new_room_tab_join')));
    await tester.pump();
    expect(targetField(tester).controller!.text, '#sala:b.c');
  });

  testWidgets('Enter com o campo vazio não faz nada e mantém o foco', (
    tester,
  ) async {
    await openJoinTab(tester);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(repository.joinedTargets, isEmpty);
    expect(targetField(tester).focusNode!.hasFocus, isTrue);
  });

  testWidgets('Enter entra e devolve JoinedRoom', (tester) async {
    await openJoinTab(tester);

    await tester.enterText(
      find.byKey(const Key('join_room_target')),
      ' #sala:b.c ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(repository.joinedTargets, ['#sala:b.c']);
    expect(find.byKey(const Key('new_room_dialog')), findsNothing);
    expect(popped, const JoinedRoom('!entrou:b.c'));
  });

  testWidgets('entrando: campo e abas bloqueados e nada fecha', (
    tester,
  ) async {
    repository.joinRoomGate = Completer<void>();
    await openJoinTab(tester);
    await tester.enterText(
      find.byKey(const Key('join_room_target')),
      '#sala:b.c',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('join_room_submit')));
    await tester.pump();

    expect(find.text('Entrando…'), findsOneWidget);
    expect(targetField(tester).enabled, isFalse);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.tap(
      find.byKey(const Key('new_room_tab_create')),
      warnIfMissed: false,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.tap(
      find.byKey(const Key('new_room_cancel')),
      warnIfMissed: false,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(find.byKey(const Key('join_room_target')), findsOneWidget);
    expect(repository.joinedTargets, hasLength(1));

    repository.joinRoomGate!.complete();
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('cada falha mostra o alerta com o texto do tipo', (
    tester,
  ) async {
    const details = {
      JoinRoomFailureType.invalidLink: 'Isso não parece um link de sala. Use um link matrix.to, um ID (!…) ou um endereço (#…).',
      JoinRoomFailureType.notFound: 'Sala não encontrada.',
      JoinRoomFailureType.forbidden: 'Essa sala só aceita quem foi convidado.',
      JoinRoomFailureType.network:
          'Sem conexão com o servidor. Seus dados continuam aqui.',
      JoinRoomFailureType.unknown: 'Erro inesperado. Tente de novo.',
    };
    await openJoinTab(tester);
    await tester.enterText(find.byKey(const Key('join_room_target')), 'xyz');
    await tester.pump();

    for (final MapEntry(key: type, value: detail) in details.entries) {
      repository.joinRoomResult = Result.error(JoinRoomFailure(type));
      await tester.tap(find.byKey(const Key('join_room_submit')));
      await tester.pump();

      expect(find.byKey(const Key('join_room_error')), findsOneWidget);
      expect(find.text('Não foi possível entrar na sala'), findsOneWidget);
      expect(find.text(detail), findsOneWidget, reason: '$type');
      expect(find.text('Tentar de novo'), findsOneWidget);
      expect(targetField(tester).controller!.text, 'xyz');
    }
    await tester.pump();
    expect(targetField(tester).focusNode!.hasFocus, isTrue);
  });
}
