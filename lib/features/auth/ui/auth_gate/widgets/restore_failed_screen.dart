import 'package:flutter/material.dart';

import '../view_models/auth_gate_view_model.dart';

class RestoreFailedScreen extends StatelessWidget {
  const RestoreFailedScreen({super.key, required this.viewModel});

  final AuthGateViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Não foi possível abrir a sessão salva.',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Verifique se o cofre de senhas do sistema está desbloqueado. '
                  'Entrar novamente substitui a sessão salva.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('restore_retry'),
                  onPressed: viewModel.retryRestore,
                  child: const Text('Tentar de novo'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('restore_skip'),
                  onPressed: viewModel.skipRestore,
                  child: const Text('Entrar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
