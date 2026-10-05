import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../view_models/auth_gate_state.dart';
import '../view_models/auth_gate_view_model.dart';
import 'authenticated_view.dart';
import 'restore_failed_screen.dart';
import 'restoring_screen.dart';
import 'unauthenticated_view.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.viewModel});

  final AuthGateViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthGateViewModel, AuthGateState>(
      bloc: viewModel,
      builder: (context, state) => switch (state) {
        AuthGateRestoring() => const RestoringScreen(),
        AuthGateRestoreFailed() => RestoreFailedScreen(viewModel: viewModel),
        AuthGateUnauthenticated() => const UnauthenticatedView(),
        AuthGateAuthenticated(:final session) => AuthenticatedView(
          // Uma sessão diferente recria a home, em vez de reaproveitar os ViewModels da anterior.
          key: ValueKey(session),
          session: session,
        ),
      },
    );
  }
}
