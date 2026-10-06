import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../app/theme.dart';
import '../../../domain/models/room_action_failure.dart';
import '../../invite_chips/view_models/invite_chips_view_model.dart';
import '../../invite_chips/widgets/invite_chips_field.dart';
import '../../new_room/widgets/room_dialog_parts.dart';
import '../view_models/invite_room_state.dart';
import '../view_models/invite_room_view_model.dart';

// Espera InviteRoomViewModel e InviteChipsViewModel no contexto.
class InviteRoomDialog extends StatefulWidget {
  const InviteRoomDialog({super.key, required this.roomName});

  final String roomName;

  @override
  State<InviteRoomDialog> createState() => _InviteRoomDialogState();
}

class _InviteRoomDialogState extends State<InviteRoomDialog> {
  Future<void> _submit() async {
    final invites = context.read<InviteChipsViewModel>();
    final viewModel = context.read<InviteRoomViewModel>();
    if (viewModel.state.sending) return;
    await invites.flush();
    if (!mounted || invites.state.blocksSubmit) return;
    await viewModel.send(invites.state.ids);
  }

  void _removeSent(InviteRoomState state) {
    final invites = context.read<InviteChipsViewModel>();
    final failed = {for (final failure in state.failures) failure.userId};
    final chips = invites.state.chips;
    // Do maior índice para o menor, para os índices restantes não mudarem.
    for (var index = chips.length - 1; index >= 0; index--) {
      if (!failed.contains(chips[index].id)) invites.removeInvite(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final invites = context.watch<InviteChipsViewModel>().state;
    return BlocConsumer<InviteRoomViewModel, InviteRoomState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) => switch (state.status) {
        InviteRoomStatus.sent => Navigator.of(context).pop(),
        InviteRoomStatus.failure => _removeSent(state),
        InviteRoomStatus.idle || InviteRoomStatus.sending => null,
      },
      builder: (context, state) {
        final busy = state.sending || state.status == InviteRoomStatus.sent;
        final hasInvites = invites.chips.isNotEmpty || invites.hasPendingQuery;
        return PopScope(
          canPop: !busy,
          child: Dialog(
            key: const Key('invite_room_dialog'),
            backgroundColor: colors.surface,
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: colors.dialogBorder),
            ),
            child: SizedBox(
              width: 460,
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
                          'Convidar para ${widget.roomName}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        InviteChipsField(
                          enabled: !busy,
                          autofocus: true,
                          fieldKey: const Key('invite_room_field'),
                          helpKey: const Key('invite_room_help'),
                          chipKeyPrefix: 'invite_room_chip',
                          hintText: '@usuario:servidor',
                          helpText: 'Digite @usuario:servidor e aperte Enter.',
                        ),
                        if (state.status == InviteRoomStatus.failure) ...[
                          const SizedBox(height: 16),
                          RoomDialogAlert(
                            key: const Key('invite_room_error'),
                            title: 'Alguns convites não foram enviados',
                            detail: _failuresDetail(state.failures),
                          ),
                        ],
                      ],
                    ),
                  ),
                  RoomDialogActions(
                    submitKey: const Key('invite_room_submit'),
                    label: state.status == InviteRoomStatus.failure
                        ? 'Tentar de novo'
                        : 'Convidar',
                    busy: busy,
                    canSubmit: !busy && hasInvites && !invites.blocksSubmit,
                    onSubmit: _submit,
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

String _failuresDetail(List<InviteFailure> failures) => [
  for (final failure in failures)
    '“${failure.userId}”: ${_failureReason(failure.type)}',
].join('\n');

String _failureReason(RoomActionFailureType type) => switch (type) {
  RoomActionFailureType.forbidden => 'sem permissão',
  RoomActionFailureType.invalidUserId => 'ID inválido',
  RoomActionFailureType.notFound => 'sala não encontrada',
  RoomActionFailureType.network => 'sem conexão',
  RoomActionFailureType.unverifiedDevice =>
    'esta sala compartilha o histórico com convidados, e para isso esta '
        'sessão precisa estar verificada. Use sua chave de recuperação e '
        'tente de novo.',
  RoomActionFailureType.unknown => 'erro inesperado',
};
