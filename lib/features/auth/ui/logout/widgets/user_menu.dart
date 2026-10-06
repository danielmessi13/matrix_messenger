import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/utils/string_extensions.dart';
import '../view_models/logout_state.dart';
import '../view_models/logout_view_model.dart';

class UserMenu extends StatefulWidget {
  const UserMenu({super.key, required this.viewModel, required this.userId});

  final LogoutViewModel viewModel;

  final String userId;

  @override
  State<UserMenu> createState() => _UserMenuState();
}

class _UserMenuState extends State<UserMenu> {
  var _open = false;

  void _setOpen(bool open) => setState(() => _open = open);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final viewModel = widget.viewModel;
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
        tooltip: null,
        enabled: state.status != LogoutStatus.running,
        offset: const Offset(0, 50),
        constraints: const BoxConstraints(minWidth: 292, maxWidth: 292),
        menuPadding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.borderStrong),
        ),
        color: colors.surfaceRaised,
        elevation: 12,
        onOpened: () => _setOpen(true),
        onCanceled: () => _setOpen(false),
        itemBuilder: (_) => [
          // Desabilitados: o header não é clicável e o "Sair" tem InkWell próprio para o hover arredondado.
          PopupMenuItem<void>(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _MenuHeader(userId: widget.userId),
          ),
          PopupMenuItem<void>(
            enabled: false,
            height: 0,
            padding: EdgeInsets.zero,
            child: Divider(height: 13, thickness: 1, color: colors.border),
          ),
          PopupMenuItem<void>(
            enabled: false,
            height: 0,
            padding: EdgeInsets.zero,
            child: _LogoutItem(onTap: viewModel.logout),
          ),
        ],
        child: _Trigger(userId: widget.userId, open: _open),
      ),
    );
  }
}

class _Trigger extends StatelessWidget {
  const _Trigger({required this.userId, required this.open});

  final String userId;

  final bool open;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 42,
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Avatar(userId: userId, radius: 16),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              userId.userLocalpart,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          AnimatedRotation(
            turns: open ? 0.5 : 0,
            duration: const Duration(milliseconds: 150),
            child: Icon(
              Icons.arrow_drop_down,
              size: 22,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 10),
      child: Row(
        children: [
          _Avatar(userId: userId, radius: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userId.userLocalpart,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  userId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: colors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoutItem extends StatelessWidget {
  const _LogoutItem({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      key: const Key('logout'),
      borderRadius: BorderRadius.circular(8),
      hoverColor: colors.surfaceHigh,
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Container(
        height: 36,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(
          'Sair',
          style: TextStyle(fontSize: 14, color: colors.textPrimary),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.userId, required this.radius});

  final String userId;

  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors.surfaceHigh,
      child: Text(
        userId.userInitials,
        style: TextStyle(
          fontSize: radius * 0.75,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}
