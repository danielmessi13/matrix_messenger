import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../view_models/logout_state.dart';
import '../view_models/logout_view_model.dart';

class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key, required this.viewModel});

  final LogoutViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LogoutViewModel, LogoutState>(
      bloc: viewModel,
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        final messenger = ScaffoldMessenger.of(context);
        if (state.status == LogoutStatus.running) {
          messenger.hideCurrentSnackBar();
        }
        if (state.status != LogoutStatus.failure) return;
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Não foi possível sair.'),
            action: SnackBarAction(
              label: 'Tentar de novo',
              onPressed: viewModel.logout,
            ),
          ),
        );
      },
      builder: (context, state) => IconButton(
        key: const Key('logout'),
        tooltip: 'Sair',
        icon: const Icon(Icons.logout),
        onPressed: state.status == LogoutStatus.running
            ? null
            : viewModel.logout,
      ),
    );
  }
}
