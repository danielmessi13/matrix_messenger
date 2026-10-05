import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/utils/string_extensions.dart';
import '../view_models/logout_state.dart';
import '../view_models/logout_view_model.dart';

class UserMenu extends StatelessWidget {
  const UserMenu({super.key, required this.viewModel, required this.userId});

  final LogoutViewModel viewModel;

  final String userId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
      builder: (context, state) => PopupMenuButton<void>(
        key: const Key('user_menu'),
        tooltip: userId,
        enabled: state.status != LogoutStatus.running,
        offset: const Offset(0, 44),
        borderRadius: BorderRadius.circular(18),
        color: colors.surfaceRaised,
        itemBuilder: (_) => [
          PopupMenuItem<void>(
            key: const Key('logout'),
            onTap: viewModel.logout,
            child: const Text('Sair'),
          ),
        ],
        child: CircleAvatar(
          radius: 18,
          backgroundColor: colors.surfaceHigh,
          child: Text(
            userId.userInitials,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
