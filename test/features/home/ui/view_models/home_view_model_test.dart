import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/auth/domain/models/user_session.dart';
import 'package:matrix_messenger/features/home/ui/view_models/home_state.dart';
import 'package:matrix_messenger/features/home/ui/view_models/home_view_model.dart';

import '../../../../../testing/models/user_session.dart';

void main() {
  const unsavedSession = UserSession(
    userId: '@alice:matrix.org',
    deviceId: 'DEVICE123',
    sessionSaved: false,
  );

  test('estado inicial: filtros recolhidos e lista expandida', () async {
    final viewModel = HomeViewModel(kUserSession);

    expect(viewModel.state, const HomeState(session: kUserSession));
    expect(viewModel.state.filtersExpanded, isFalse);
    expect(viewModel.state.roomListExpanded, isTrue);
    await viewModel.close();
  });

  test('janela estreita começa com a lista recolhida', () async {
    final viewModel = HomeViewModel(kUserSession, roomListExpanded: false);

    expect(viewModel.state.roomListExpanded, isFalse);
    await viewModel.close();
  });

  blocTest<HomeViewModel, HomeState>(
    'alterna filtros e lista',
    build: () => HomeViewModel(kUserSession),
    act: (viewModel) => viewModel
      ..toggleFilters()
      ..toggleRoomList(),
    expect: () => const [
      HomeState(session: kUserSession, filtersExpanded: true),
      HomeState(
        session: kUserSession,
        filtersExpanded: true,
        roomListExpanded: false,
      ),
    ],
  );

  test('aviso de sessão não salva aparece só quando falta o cofre', () {
    expect(const HomeState(session: kUserSession).showSessionWarning, isFalse);
    expect(const HomeState(session: unsavedSession).showSessionWarning, isTrue);
  });

  blocTest<HomeViewModel, HomeState>(
    'dispensar o aviso esconde até a próxima sessão',
    build: () => HomeViewModel(unsavedSession),
    act: (viewModel) => viewModel.dismissSessionWarning(),
    verify: (viewModel) => expect(viewModel.state.showSessionWarning, isFalse),
  );

  test('thread aberta e fechada', () async {
    final viewModel = HomeViewModel(kUserSession)
      ..threadVisibilityChanged(true);

    expect(viewModel.state.threadOpen, isTrue);
    viewModel.threadVisibilityChanged(false);
    expect(viewModel.state.threadOpen, isFalse);
    await viewModel.close();
  });

  test(
    'abrir a lista à mão com a thread aberta deixa a thread por cima',
    () async {
      final viewModel = HomeViewModel(kUserSession)
        ..threadVisibilityChanged(true)
        ..expandRoomList(width: 1440);

      expect(viewModel.state.roomListExpanded, isTrue);
      expect(viewModel.state.panesOverThreadWidth, 1440);
      viewModel.threadVisibilityChanged(false);
      expect(viewModel.state.panesOverThreadWidth, isNull);
      await viewModel.close();
    },
  );

  test('abrir os filtros à mão sem thread não muda a sobreposição', () async {
    final viewModel = HomeViewModel(kUserSession)..expandFilters(width: 1440);

    expect(viewModel.state.filtersExpanded, isTrue);
    expect(viewModel.state.panesOverThreadWidth, isNull);
    await viewModel.close();
  });

  test('aviso de thread depois de fechado não quebra', () async {
    final viewModel = HomeViewModel(kUserSession);
    await viewModel.close();

    expect(() => viewModel.threadVisibilityChanged(false), returnsNormally);
  });
}
