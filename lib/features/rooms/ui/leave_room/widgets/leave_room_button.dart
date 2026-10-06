import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../app/theme.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../domain/models/room_action_failure.dart';
import '../../new_room/widgets/room_dialog_parts.dart';
import '../view_models/leave_room_state.dart';
import '../view_models/leave_room_view_model.dart';

class LeaveRoomButton extends StatelessWidget {
  const LeaveRoomButton({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  final String roomId;

  final String roomName;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('leave_room'),
    tooltip: 'Sair da sala',
    iconSize: 18,
    color: context.colors.textSecondary,
    icon: const Icon(Icons.logout),
    onPressed: () {
      final repository = context.read<RoomRepository>();
      // O view model fica com o diálogo: o header some quando o sync tira a sala.
      showDialog<void>(
        context: context,
        builder: (_) => BlocProvider(
          create: (_) => LeaveRoomViewModel(repository, roomId),
          child: _LeaveRoomDialog(roomName: roomName),
        ),
      );
    },
  );
}

class _LeaveRoomDialog extends StatelessWidget {
  const _LeaveRoomDialog({required this.roomName});

  final String roomName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BlocConsumer<LeaveRoomViewModel, LeaveRoomState>(
      listenWhen: (previous, current) =>
          previous.status != current.status &&
          current.status == LeaveRoomStatus.left,
      listener: (context, state) => Navigator.of(context).pop(),
      builder: (context, state) {
        final busy =
            state.status == LeaveRoomStatus.leaving ||
            state.status == LeaveRoomStatus.left;
        return PopScope(
          canPop: !busy,
          child: Dialog(
            key: const Key('leave_room_dialog'),
            backgroundColor: colors.surface,
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: colors.dialogBorder),
            ),
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Sair de $roomName?',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Você deixa de receber mensagens desta sala. Para '
                          'voltar a uma sala privada, você vai precisar de um '
                          'novo convite.',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: colors.textSecondary,
                          ),
                        ),
                        if (state.status == LeaveRoomStatus.failure) ...[
                          const SizedBox(height: 16),
                          RoomDialogAlert(
                            key: const Key('leave_room_error'),
                            title: 'Não foi possível sair da sala',
                            detail: _failureDetail(state.failure),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _LeaveRoomActions(
                    busy: busy,
                    label: state.status == LeaveRoomStatus.failure
                        ? 'Tentar de novo'
                        : 'Sair',
                    onConfirm: context.read<LeaveRoomViewModel>().leave,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LeaveRoomActions extends StatelessWidget {
  const _LeaveRoomActions({
    required this.busy,
    required this.label,
    required this.onConfirm,
  });

  final bool busy;

  final String label;

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            key: const Key('leave_room_cancel'),
            onPressed: busy ? null : () => Navigator.of(context).maybePop(),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              visualDensity: VisualDensity.standard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Cancelar',
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('leave_room_confirm'),
            onPressed: busy ? null : onConfirm,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              visualDensity: VisualDensity.standard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              backgroundColor: colors.danger,
              foregroundColor: colors.onAccent,
              disabledBackgroundColor: colors.danger,
              disabledForegroundColor: colors.onAccent,
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy) ...[
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(label),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _failureDetail(RoomActionFailureType? failure) => switch (failure) {
  RoomActionFailureType.network =>
    'Sem conexão com o servidor. Tente de novo em instantes.',
  RoomActionFailureType.forbidden => 'O servidor não permitiu sair desta sala.',
  _ => 'Erro inesperado. Tente de novo.',
};
