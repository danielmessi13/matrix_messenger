import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/ui/logout/view_models/logout_view_model.dart';
import '../../../auth/ui/logout/widgets/user_menu.dart';
import '../../../conversation/ui/widgets/conversation_pane.dart';
import '../../../rooms/ui/room_list/view_models/room_list_state.dart';
import '../../../rooms/ui/room_list/view_models/room_list_view_model.dart';
import '../../../rooms/ui/room_list/widgets/filter_rail.dart';
import '../../../rooms/ui/room_list/widgets/room_list_pane.dart';
import '../../../rooms/ui/room_list/widgets/room_search_field.dart';
import '../view_models/home_state.dart';
import '../view_models/home_view_model.dart';
import 'top_bar.dart';

const kWideLayoutWidth = 1200.0;

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.viewModel,
    required this.roomListViewModel,
    this.clock = DateTime.now,
  });

  final HomeViewModel viewModel;

  final RoomListViewModel roomListViewModel;

  final DateTime Function() clock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchFocus = FocusNode(debugLabel: 'room_search');

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rooms = widget.roomListViewModel;
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    return BlocProvider(
      create: (context) => LogoutViewModel(context.read<AuthRepository>()),
      child: CallbackShortcuts(
        bindings: {
          SingleActivator(
            LogicalKeyboardKey.keyK,
            control: !isMac,
            meta: isMac,
          ): _searchFocus.requestFocus,
        },
        // Scope próprio: o unfocus da busca devolve o foco para cá, dentro do atalho.
        child: FocusScope(
          autofocus: true,
          child: BlocBuilder<HomeViewModel, HomeState>(
            bloc: widget.viewModel,
            builder: (context, home) =>
                BlocBuilder<RoomListViewModel, RoomListState>(
                  bloc: rooms,
                  builder: (context, list) => Scaffold(
                    key: const Key('home_screen'),
                    body: Column(
                      children: [
                        TopBar(
                          searchField: RoomSearchField(
                            focusNode: _searchFocus,
                            onChanged: rooms.search,
                            onCleared: rooms.clearSearch,
                          ),
                          userMenu: UserMenu(
                            viewModel: context.read<LogoutViewModel>(),
                            userId: home.session.userId,
                          ),
                        ),
                        if (home.showSessionWarning)
                          _SessionWarningBanner(
                            onDismiss: widget.viewModel.dismissSessionWarning,
                          ),
                        Expanded(
                          child: _Panes(
                            home: home,
                            list: list,
                            viewModel: widget.viewModel,
                            roomListViewModel: rooms,
                            now: widget.clock(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
  }
}

class _SessionWarningBanner extends StatelessWidget {
  const _SessionWarningBanner({required this.onDismiss})
    : super(key: const Key('session_not_saved'));

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => MaterialBanner(
    content: const Text(
      'Não foi possível salvar a sessão neste computador. '
      'Você precisará entrar de novo da próxima vez que abrir o app.',
    ),
    actions: [TextButton(onPressed: onDismiss, child: const Text('Entendi'))],
  );
}

class _Panes extends StatelessWidget {
  const _Panes({
    required this.home,
    required this.list,
    required this.viewModel,
    required this.roomListViewModel,
    required this.now,
  });

  final HomeState home;

  final RoomListState list;

  final HomeViewModel viewModel;

  final RoomListViewModel roomListViewModel;

  final DateTime now;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilterRail(
        expanded: home.filtersExpanded,
        selected: list.filter,
        unreadByFilter: list.unreadByFilter,
        onSelect: roomListViewModel.selectFilter,
        onToggle: viewModel.toggleFilters,
      ),
      RoomListPane(
        expanded: home.roomListExpanded,
        state: list,
        now: now,
        onSelect: roomListViewModel.selectRoom,
        onToggle: viewModel.toggleRoomList,
      ),
      Expanded(child: ConversationPane(room: list.selectedRoom)),
    ],
  );
}
