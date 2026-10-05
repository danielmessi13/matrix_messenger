import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../features/auth/data/repositories/auth_repository.dart';
import '../features/auth/ui/auth_gate/view_models/auth_gate_view_model.dart';
import '../features/auth/ui/auth_gate/widgets/auth_gate.dart';
import 'theme.dart';

class MessengerApp extends StatelessWidget {
  const MessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matrix Messenger',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: BlocProvider(
        create: (context) =>
            AuthGateViewModel(context.read<AuthRepository>())..init(),
        child: Builder(
          builder: (context) =>
              AuthGate(viewModel: context.read<AuthGateViewModel>()),
        ),
      ),
    );
  }
}
