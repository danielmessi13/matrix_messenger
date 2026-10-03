import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../features/auth/data/repositories/auth_repository.dart';
import '../features/auth/ui/auth_gate/view_models/auth_gate_view_model.dart';
import '../features/auth/ui/auth_gate/widgets/auth_gate.dart';

class MessengerApp extends StatelessWidget {
  const MessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0DBD8B);
    return MaterialApp(
      title: 'Matrix Messenger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
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
