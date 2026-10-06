import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../app/theme.dart';
import '../../../data/repositories/room_repository.dart';
import '../view_models/room_link_view_model.dart';

class CopyRoomLinkButton extends StatefulWidget {
  const CopyRoomLinkButton({super.key, required this.roomId});

  final String roomId;

  @override
  State<CopyRoomLinkButton> createState() => _CopyRoomLinkButtonState();
}

class _CopyRoomLinkButtonState extends State<CopyRoomLinkButton> {
  final _tooltip = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        RoomLinkViewModel(context.read<RoomRepository>(), widget.roomId),
    child: BlocConsumer<RoomLinkViewModel, RoomLinkStatus>(
      listenWhen: (previous, current) =>
          current == RoomLinkStatus.copied || current == RoomLinkStatus.failure,
      // O clique do mouse esconde a dica; sem reabrir, o resultado passa batido.
      listener: (context, status) =>
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _tooltip.currentState?.ensureTooltipVisible(),
          ),
      builder: (context, status) {
        final colors = context.colors;
        return Tooltip(
          key: _tooltip,
          message: switch (status) {
            RoomLinkStatus.copied => 'Link copiado',
            RoomLinkStatus.failure => 'Não foi possível copiar o link',
            RoomLinkStatus.idle ||
            RoomLinkStatus.copying => 'Copiar link da sala',
          },
          child: IconButton(
            key: const Key('copy_room_link'),
            iconSize: 18,
            color: switch (status) {
              RoomLinkStatus.copied => colors.accent,
              RoomLinkStatus.failure => colors.danger,
              RoomLinkStatus.idle || RoomLinkStatus.copying => colors.textMuted,
            },
            onPressed: status == RoomLinkStatus.copying
                ? null
                : context.read<RoomLinkViewModel>().copy,
            icon: Icon(switch (status) {
              RoomLinkStatus.copied => Icons.check,
              RoomLinkStatus.failure => Icons.error_outline,
              RoomLinkStatus.idle || RoomLinkStatus.copying => Icons.link,
            }),
          ),
        );
      },
    ),
  );
}
