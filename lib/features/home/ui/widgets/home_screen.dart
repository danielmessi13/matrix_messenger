import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/ui/logout/view_models/logout_view_model.dart';
import '../../../auth/ui/logout/widgets/logout_button.dart';
import '../view_models/home_state.dart';
import '../view_models/home_view_model.dart';

// TODO: substituir pela lista de salas.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.viewModel});

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return BlocBuilder<HomeViewModel, HomeState>(
      bloc: viewModel,
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          actions: [
            BlocProvider(
              create: (context) =>
                  LogoutViewModel(context.read<AuthRepository>()),
              child: Builder(
                builder: (context) =>
                    LogoutButton(viewModel: context.read<LogoutViewModel>()),
              ),
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 48),
              const SizedBox(height: 16),
              Text('Conectado como', style: textTheme.titleMedium),
              const SizedBox(height: 4),
              SelectableText(
                state.session.userId,
                style: textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              SelectableText(
                'Device ${state.session.deviceId}',
                style: textTheme.bodySmall,
              ),
              if (!state.session.sessionSaved) ...[
                const SizedBox(height: 24),
                Text(
                  'Não foi possível salvar a sessão neste computador. '
                  'Você precisará entrar de novo da próxima vez que abrir o app.',
                  key: const Key('session_not_saved'),
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
