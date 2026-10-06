import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/recovery/domain/models/recovery_failure.dart';
import 'package:matrix_messenger/features/recovery/domain/models/recovery_status.dart';
import 'package:matrix_messenger/features/recovery/ui/view_models/recovery_view_model.dart';
import 'package:matrix_messenger/features/recovery/ui/widgets/recovery_banner.dart';

import '../../../../../testing/fakes/repositories/fake_recovery_repository.dart';

void main() {
  late FakeRecoveryRepository repository;
  late RecoveryViewModel viewModel;

  setUp(() => repository = FakeRecoveryRepository());

  tearDown(() => repository.dispose());

  Future<void> pumpBanner(
    WidgetTester tester, [
    RecoveryStatus status = RecoveryStatus.incomplete,
  ]) async {
    // Criado dentro do teste para o stream rodar no relógio falso do tester.
    viewModel = RecoveryViewModel(repository)..init();
    addTearDown(viewModel.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: RecoveryBanner(viewModel: viewModel)),
      ),
    );
    repository.statusController.add(status);
    await tester.pump();
  }

  Future<void> submitKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(const Key('recovery_open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('recovery_key')), key);
    await tester.tap(find.byKey(const Key('recovery_submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('não aparece quando o backup já está acessível', (tester) async {
    await pumpBanner(tester, RecoveryStatus.enabled);

    expect(find.byKey(const Key('recovery_banner')), findsNothing);
  });

  testWidgets('"Agora não" esconde o banner', (tester) async {
    await pumpBanner(tester);
    expect(find.byKey(const Key('recovery_banner')), findsOneWidget);

    await tester.tap(find.text('Agora não'));
    await tester.pump();

    expect(find.byKey(const Key('recovery_banner')), findsNothing);
  });

  testWidgets('chave inválida mostra o erro e mantém o diálogo', (
    tester,
  ) async {
    repository.recoverResult = const Result.error(
      RecoveryFailure(RecoveryFailureType.invalidKey),
    );
    await pumpBanner(tester);

    await submitKey(tester, 'errada');

    expect(find.byKey(const Key('recovery_dialog')), findsOneWidget);
    expect(find.text('Chave de recuperação inválida.'), findsOneWidget);
  });

  testWidgets('sucesso fecha o diálogo e o banner', (tester) async {
    await pumpBanner(tester);

    await submitKey(tester, 'EsTx 1234');

    expect(repository.recoveredWith, ['EsTx 1234']);
    expect(find.byKey(const Key('recovery_dialog')), findsNothing);
    expect(find.byKey(const Key('recovery_banner')), findsNothing);
  });
}
