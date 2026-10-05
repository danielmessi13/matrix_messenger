import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../home/ui/view_models/home_view_model.dart';
import '../../../../home/ui/widgets/home_screen.dart';
import '../../../../rooms/data/repositories/room_repository.dart';
import '../../../../rooms/ui/room_list/view_models/room_list_view_model.dart';
import '../../../domain/models/user_session.dart';

class AuthenticatedView extends StatelessWidget {
  const AuthenticatedView({super.key, required this.session});

  final UserSession session;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= kWideLayoutWidth;
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => HomeViewModel(session, roomListExpanded: wide),
        ),
        BlocProvider(
          create: (context) {
            return RoomListViewModel(context.read<RoomRepository>())..init();
          },
        ),
      ],
      child: Builder(
        builder: (context) => HomeScreen(
          viewModel: context.read<HomeViewModel>(),
          roomListViewModel: context.read<RoomListViewModel>(),
        ),
      ),
    );
  }
}
