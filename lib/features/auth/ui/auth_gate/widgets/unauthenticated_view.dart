import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/services/browser_launcher.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../login/view_models/login_view_model.dart';
import '../../login/widgets/login_screen.dart';

class UnauthenticatedView extends StatelessWidget {
  const UnauthenticatedView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => LoginViewModel(
        context.read<AuthRepository>(),
        context.read<BrowserLauncher>(),
      ),
      child: Builder(
        builder: (context) => LoginScreen(
          viewModel: context.read<LoginViewModel>(),
        ),
      ),
    );
  }
}
