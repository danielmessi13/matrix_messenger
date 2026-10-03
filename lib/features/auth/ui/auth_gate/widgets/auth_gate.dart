import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../home/ui/view_models/home_view_model.dart';
import '../../../../home/ui/widgets/home_screen.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../login/view_models/login_view_model.dart';
import '../../login/widgets/login_screen.dart';
import '../view_models/auth_gate_state.dart';
import '../view_models/auth_gate_view_model.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.viewModel});

  final AuthGateViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthGateViewModel, AuthGateState>(
      bloc: viewModel,
      builder: (context, state) => switch (state) {
        AuthGateRestoring() => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        AuthGateUnauthenticated() => BlocProvider(
          create: (context) => LoginViewModel(context.read<AuthRepository>()),
          child: Builder(
            builder: (context) =>
                LoginScreen(viewModel: context.read<LoginViewModel>()),
          ),
        ),
        AuthGateAuthenticated(:final session) => BlocProvider(
          // Uma sessão diferente recria a home, em vez de reaproveitar o ViewModel da anterior.
          key: ValueKey(session),
          create: (context) => HomeViewModel(session),
          child: Builder(
            builder: (context) =>
                HomeScreen(viewModel: context.read<HomeViewModel>()),
          ),
        ),
      },
    );
  }
}
