import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/home/ui/view_models/home_state.dart';
import 'package:matrix_messenger/features/home/ui/view_models/home_view_model.dart';

import '../../../../../testing/models/user_session.dart';

void main() {
  test('estado inicial mostra a sessão recebida', () async {
    final viewModel = HomeViewModel(kUserSession);

    expect(viewModel.state, const HomeState(session: kUserSession));
    await viewModel.close();
  });
}
