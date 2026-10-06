import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/ui/logout/view_models/logout_view_model.dart';
import '../../../auth/ui/logout/widgets/user_menu.dart';
import '../../../conversation/ui/widgets/conversation_pane.dart';
import '../../../recovery/data/repositories/recovery_repository.dart';
import '../../../recovery/ui/view_models/recovery_view_model.dart';
import '../../../recovery/ui/widgets/recovery_banner.dart';
import '../../../rooms/data/repositories/room_repository.dart';
import '../../../rooms/domain/models/new_room.dart';
import '../../../rooms/domain/models/room_filter.dart';
import '../../../rooms/ui/new_room/view_models/join_room_view_model.dart';
import '../../../rooms/ui/new_room/view_models/new_room_view_model.dart';
import '../../../rooms/ui/new_room/widgets/new_room_button.dart';
import '../../../rooms/ui/new_room/widgets/new_room_dialog.dart';
import '../../../rooms/ui/room_list/view_models/room_list_state.dart';
import '../../../rooms/ui/room_list/view_models/room_list_view_model.dart';
import '../../../rooms/ui/room_list/widgets/filter_rail.dart';
import '../../../rooms/ui/room_list/widgets/room_list_pane.dart';
import '../../../rooms/ui/room_list/widgets/room_search_field.dart';
import '../../../threads/ui/view_models/recent_threads_state.dart';
import '../../../threads/ui/view_models/recent_threads_view_model.dart';
import '../../../threads/ui/widgets/recent_threads_pane.dart';
import '../view_models/home_state.dart';
import '../view_models/home_view_model.dart';
import 'top_bar.dart';

const kWideLayoutWidth = 1200.0;

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.viewModel,
    required this.roomListViewModel,
    required this.recentThreadsViewModel,
    this.clock = DateTime.now,
  });

  final HomeViewModel viewModel;

  final RoomListViewModel roomListViewModel;

  final RecentThreadsViewModel recentThreadsViewModel;

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

  Future<void> _openNewRoom() async {
    final repository = context.read<RoomRepository>();
    final result = await showDialog<NewRoomResult>(
      context: context,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => NewRoomViewModel(repository)),
          BlocProvider(create: (_) => JoinRoomViewModel(repository)),
        ],
        child: const NewRoomDialog(),
      ),
    );
    if (result == null || !mounted) return;
    widget.roomListViewModel.selectWhenAvailable(result.roomId);
    if (result case CreatedRoom(:final failedInvites)) {
      // Lista vazia limpa o banner de uma criação anterior.
      widget.viewModel.showFailedInvites(failedInvites);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = widget.roomListViewModel;
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => LogoutViewModel(context.read<AuthRepository>()),
        ),
        BlocProvider(
          create: (context) =>
              RecoveryViewModel(context.read<RecoveryRepository>())..init(),
        ),
      ],
      child: CallbackShortcuts(
        bindings: {
          SingleActivator(
            LogicalKeyboardKey.keyK,
            control: !isMac,
            meta: isMac,
          ): _searchFocus.requestFocus,
          SingleActivator(
            LogicalKeyboardKey.keyN,
            control: !isMac,
            meta: isMac,
          ): _openNewRoom,
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
                          newRoomButton: NewRoomButton(onPressed: _openNewRoom),
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
                        if (home.failedInvites.isNotEmpty)
                          _FailedInvitesBanner(
                            ids: home.failedInvites,
                            onDismiss: widget.viewModel.dismissFailedInvites,
                          ),
                        RecoveryBanner(
                          viewModel: context.read<RecoveryViewModel>(),
                        ),
                        Expanded(
                          child: _Panes(
                            home: home,
                            list: list,
                            viewModel: widget.viewModel,
                            roomListViewModel: rooms,
                            recentThreadsViewModel:
                                widget.recentThreadsViewModel,
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

class _FailedInvitesBanner extends StatelessWidget {
  const _FailedInvitesBanner({required this.ids, required this.onDismiss})
    : super(key: const Key('failed_invites_banner'));

  final List<String> ids;

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.1),
        border: Border.all(color: colors.warning.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.warningText, width: 1.5),
            ),
            child: Text(
              '!',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.warningText,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sala criada, mas alguns convites não foram enviados',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    text: 'Estes IDs não foram convidados: ',
                    style: TextStyle(color: colors.textSecondary),
                    children: [
                      TextSpan(
                        text: ids.join(', '),
                        style: TextStyle(color: colors.textPrimary),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('failed_invites_dismiss'),
            tooltip: 'Dispensar',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            color: colors.textMuted,
            onPressed: onDismiss,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _Panes extends StatelessWidget {
  const _Panes({
    required this.home,
    required this.list,
    required this.viewModel,
    required this.roomListViewModel,
    required this.recentThreadsViewModel,
    required this.now,
  });

  final HomeState home;

  final RoomListState list;

  final HomeViewModel viewModel;

  final RoomListViewModel roomListViewModel;

  final RecentThreadsViewModel recentThreadsViewModel;

  final DateTime now;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final panes = visiblePanes(home, box.maxWidth);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterRail(
            expanded: panes.filters,
            selected: list.filter,
            unreadByFilter: list.unreadByFilter,
            onSelect: roomListViewModel.selectFilter,
            onToggle: panes.filters
                ? viewModel.toggleFilters
                : () => viewModel.expandFilters(width: box.maxWidth),
          ),
          // O filtro decide antes da busca: com Threads a lista de threads fica.
          if (list.filter == RoomFilter.threads)
            BlocBuilder<RecentThreadsViewModel, RecentThreadsState>(
              bloc: recentThreadsViewModel,
              builder: (context, threads) => RecentThreadsPane(
                expanded: panes.list,
                state: threads,
                rooms: list.rooms,
                selectedRoomId: list.selectedRoomId,
                openThreadId: home.openThreadId,
                now: now,
                onSelect: (thread) => roomListViewModel.selectThread(
                  thread.roomId,
                  thread.rootEventId,
                ),
                onRetry: recentThreadsViewModel.retry,
                onToggle: panes.list
                    ? viewModel.toggleRoomList
                    : () => viewModel.expandRoomList(width: box.maxWidth),
              ),
            )
          else
            RoomListPane(
              expanded: panes.list,
              state: list,
              now: now,
              onSelect: roomListViewModel.selectRoom,
              onToggle: panes.list
                  ? viewModel.toggleRoomList
                  : () => viewModel.expandRoomList(width: box.maxWidth),
              onOpenMessage: roomListViewModel.openMessage,
              onLoadMoreMessages: roomListViewModel.loadMoreMessages,
              onRetryMessages: roomListViewModel.retryMessageSearch,
            ),
          Expanded(
            child: ConversationPane(
              room: list.selectedRoom,
              now: now,
              focus: list.focus,
              threadRequest: list.threadRequest,
              onThreadOpenChanged: viewModel.threadVisibilityChanged,
              onOpenThreadChanged: viewModel.openThreadChanged,
            ),
          ),
        ],
      );
    },
  );
}

// Com a thread aberta, recolhe lista e filtros que tirariam o espaço dela ao lado da conversa.
({bool filters, bool list}) visiblePanes(HomeState home, double width) {
  var filters = home.filtersExpanded;
  var list = home.roomListExpanded;
  final keptWidth = home.panesOverThreadWidth;
  if (!home.threadOpen || (keptWidth != null && width >= keptWidth)) {
    return (filters: filters, list: list);
  }
  double needed() =>
      (filters ? kFilterRailWidth : kFilterRailCompactWidth) +
      (list ? kRoomListWidth : kRoomListCompactWidth) +
      kThreadSideBySideWidth;
  if (list && needed() > width) list = false;
  if (filters && needed() > width) filters = false;
  return (filters: filters, list: list);
}
