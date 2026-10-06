import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/rooms/ui/invite_chips/view_models/invite_chips_view_model.dart';
import 'package:matrix_messenger/features/rooms/ui/invite_chips/widgets/invite_chips_field.dart';

import '../../../../../../testing/fakes/repositories/fake_room_repository.dart';

void main() {
  late FakeRoomRepository repository;
  late InviteChipsViewModel viewModel;

  setUp(() {
    repository = FakeRoomRepository();
    viewModel = InviteChipsViewModel(repository, exclude: const {'@eu:b.co'});
  });

  tearDown(() async {
    await viewModel.close();
    await repository.dispose();
  });

  String fieldText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('invite_field')))
      .controller!
      .text;

  Future<void> pumpField(WidgetTester tester, {bool autofocus = false}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: BlocProvider.value(
              value: viewModel,
              child: InviteChipsField(
                autofocus: autofocus,
                fieldKey: const Key('invite_field'),
                helpKey: const Key('invite_help'),
                chipKeyPrefix: 'invite_chip',
                helpText: 'Digite @usuario:servidor e aperte Enter.',
              ),
            ),
          ),
        ),
      );

  testWidgets('autofocus é repassado ao campo, desligado por padrão', (
    tester,
  ) async {
    TextField field() =>
        tester.widget<TextField>(find.byKey(const Key('invite_field')));

    await pumpField(tester);
    expect(field().autofocus, isFalse);

    await pumpField(tester, autofocus: true);
    expect(field().autofocus, isTrue);
  });

  testWidgets('usa as keys e o texto de ajuda recebidos', (tester) async {
    await pumpField(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('invite_help'))).data,
      'Digite @usuario:servidor e aperte Enter.',
    );

    await tester.enterText(
      find.byKey(const Key('invite_field')),
      '@ana:b.co @eu:b.co ',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('invite_chip_@ana:b.co')), findsOneWidget);
    expect(find.byKey(const Key('invite_chip_@eu:b.co')), findsNothing);

    await tester.tap(find.byKey(const Key('invite_chip_remove_@ana:b.co')));
    await tester.pumpAndSettle();
    expect(viewModel.state.chips, isEmpty);
  });

  testWidgets('Enter vira chip', (tester) async {
    await pumpField(tester);

    await tester.enterText(find.byKey(const Key('invite_field')), '@ana:b.co');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(viewModel.state.ids, ['@ana:b.co']);
    expect(fieldText(tester), isEmpty);
  });

  testWidgets('Backspace no campo vazio devolve o último chip ao texto', (
    tester,
  ) async {
    await pumpField(tester);
    for (final id in ['@a:x.org', '@b:y.org']) {
      await tester.enterText(find.byKey(const Key('invite_field')), id);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('invite_chip_@b:y.org')), findsNothing);
    expect(find.byKey(const Key('invite_chip_@a:x.org')), findsOneWidget);
    expect(fieldText(tester), '@b:y.org');
    final controller = tester
        .widget<TextField>(find.byKey(const Key('invite_field')))
        .controller!;
    expect(controller.selection, const TextSelection.collapsed(offset: 8));

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(fieldText(tester), '@b:y.or');

    await tester.enterText(find.byKey(const Key('invite_field')), '@b:y.org');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(viewModel.state.ids, ['@a:x.org', '@b:y.org']);
    expect(fieldText(tester), isEmpty);
  });
}
