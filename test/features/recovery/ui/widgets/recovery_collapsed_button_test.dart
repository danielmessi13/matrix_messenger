import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/recovery/domain/models/recovery_status.dart';
import 'package:matrix_messenger/features/recovery/ui/view_models/recovery_view_model.dart';
import 'package:matrix_messenger/features/recovery/ui/widgets/recovery_collapsed_button.dart';

import '../../../../../testing/fakes/repositories/fake_recovery_repository.dart';

void main() {
  late FakeRecoveryRepository repository;
  late RecoveryViewModel viewModel;
  late int presses;

  setUp(() {
    repository = FakeRecoveryRepository();
    presses = 0;
  });

  tearDown(() => repository.dispose());

  Future<void> pumpButton(WidgetTester tester, RecoveryStatus status) async {
    viewModel = RecoveryViewModel(repository)..init();
    addTearDown(viewModel.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: RecoveryCollapsedButton(
              viewModel: viewModel,
              onPressed: () => presses++,
            ),
          ),
        ),
      ),
    );
    repository.statusController.add(status);
    await tester.pump();
  }

  testWidgets('aparece com tooltip e o clique chama onPressed', (
    tester,
  ) async {
    await pumpButton(tester, RecoveryStatus.incomplete);

    expect(
      find.byTooltip(
        'Mensagens antigas trancadas · configure a chave de recuperação',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('!'));
    expect(presses, 1);
  });

  testWidgets('não aparece com o backup acessível', (tester) async {
    await pumpButton(tester, RecoveryStatus.enabled);

    expect(find.byKey(const Key('recovery_collapsed')), findsNothing);
  });

  testWidgets('some depois de finish', (tester) async {
    await pumpButton(tester, RecoveryStatus.incomplete);

    // O emit chega ao BlocBuilder por microtask; sem isso o pump já desenhou o frame antigo.
    viewModel.finish();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recovery_collapsed')), findsNothing);
  });

  testWidgets('sem backup mostra o "!" com o tooltip de configurar', (
    tester,
  ) async {
    await pumpButton(tester, RecoveryStatus.disabled);

    expect(find.byKey(const Key('recovery_collapsed')), findsOneWidget);
    expect(
      find.byTooltip('Mensagens sem backup · configure a recuperação'),
      findsOneWidget,
    );
  });
}
