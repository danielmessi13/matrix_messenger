import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/recovery/data/repositories/recovery_repository.dart';
import 'package:matrix_messenger/features/recovery/domain/models/recovery_status.dart';
import 'package:matrix_messenger/features/recovery/ui/view_models/recovery_view_model.dart';
import 'package:matrix_messenger/features/recovery/ui/widgets/recovery_card.dart';

import '../../../../../testing/fakes/repositories/fake_recovery_repository.dart';

void main() {
  late FakeRecoveryRepository repository;
  late RecoveryViewModel viewModel;

  setUp(() => repository = FakeRecoveryRepository());

  tearDown(() => repository.dispose());

  Future<void> pumpCard(WidgetTester tester, RecoveryStatus status) async {
    // Criado dentro do teste para o stream rodar no relógio falso do tester.
    viewModel = RecoveryViewModel(repository)..init();
    addTearDown(viewModel.close);
    await tester.pumpWidget(
      RepositoryProvider<RecoveryRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: RecoveryCard(viewModel: viewModel)),
        ),
      ),
    );
    repository.statusController.add(status);
    await tester.pump();
  }

  testWidgets('aparece quando o backup está incompleto', (tester) async {
    await pumpCard(tester, RecoveryStatus.incomplete);

    expect(find.byKey(const Key('recovery_card')), findsOneWidget);
    expect(find.text('Mensagens antigas trancadas'), findsOneWidget);
  });

  testWidgets('não aparece com o backup acessível', (tester) async {
    await pumpCard(tester, RecoveryStatus.enabled);

    expect(find.byKey(const Key('recovery_card')), findsNothing);
  });

  testWidgets('some depois de finish', (tester) async {
    await pumpCard(tester, RecoveryStatus.incomplete);

    // O emit chega ao BlocBuilder por microtask; sem isso o pump já desenhou o frame antigo.
    viewModel.finish();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recovery_card')), findsNothing);
  });

  testWidgets('Configurar agora abre o modal', (tester) async {
    await pumpCard(tester, RecoveryStatus.incomplete);

    await tester.tap(find.byKey(const Key('recovery_open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recovery_dialog')), findsOneWidget);
  });

  testWidgets('sem backup mostra o cartão de configurar', (tester) async {
    await pumpCard(tester, RecoveryStatus.disabled);

    expect(find.byKey(const Key('recovery_card')), findsOneWidget);
    expect(find.text('Proteja suas mensagens'), findsOneWidget);
    expect(find.text('Mensagens antigas trancadas'), findsNothing);
  });

  testWidgets('Configurar recuperação abre o modal de setup', (tester) async {
    await pumpCard(tester, RecoveryStatus.disabled);

    await tester.tap(find.byKey(const Key('recovery_setup_open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('setup_recovery_dialog')), findsOneWidget);
  });

  testWidgets('modal continua com a chave depois que o cartão some', (
    tester,
  ) async {
    await pumpCard(tester, RecoveryStatus.disabled);
    await tester.tap(find.byKey(const Key('recovery_setup_open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setup_recovery_create')));
    await tester.pumpAndSettle();

    repository.statusController.add(RecoveryStatus.enabled);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recovery_card')), findsNothing);
    expect(find.text(kFakeRecoveryKey), findsOneWidget);
  });
}
