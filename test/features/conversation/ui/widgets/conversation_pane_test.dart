import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/conversation_pane.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';

import '../../../../../testing/desktop_size.dart';
import '../../../../../testing/models/room.dart';

void main() {
  Future<void> pump(WidgetTester tester, Room? room) => tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: ConversationPane(room: room)),
    ),
  );

  testWidgets('sem sala selecionada pede para escolher', (tester) async {
    useDesktopSize(tester);
    await pump(tester, null);

    expect(find.text('Selecione uma conversa'), findsOneWidget);
  });

  testWidgets('cabeçalho com tipo, membros, nome e avatares', (tester) async {
    useDesktopSize(tester);
    await pump(tester, kTeamRoom);

    expect(find.text('SALA · 12 MEMBROS'), findsOneWidget);
    expect(find.text('#lançamento-q4'), findsOneWidget);
    expect(find.text('CM'), findsOneWidget);
    expect(find.byTooltip('Diego Alves'), findsOneWidget);
  });

  testWidgets('campo de mensagem desenhado e desabilitado', (tester) async {
    useDesktopSize(tester);
    await pump(tester, kDirectRoom);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
    expect(find.text('Escrever para Ana Ribeiro…'), findsOneWidget);
    final send = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(send.onPressed, isNull);
  });
}
