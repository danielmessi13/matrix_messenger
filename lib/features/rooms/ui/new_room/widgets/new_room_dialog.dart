import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../app/theme.dart';
import '../../../domain/models/create_room_failure.dart';
import '../../../domain/models/new_room.dart';
import '../../invite_chips/view_models/invite_chips_view_model.dart';
import '../../invite_chips/widgets/invite_chips_field.dart';
import '../view_models/join_room_state.dart';
import '../view_models/join_room_view_model.dart';
import '../view_models/new_room_state.dart';
import '../view_models/new_room_view_model.dart';
import 'join_room_form.dart';
import 'room_dialog_parts.dart';

class NewRoomDialog extends StatefulWidget {
  const NewRoomDialog({super.key});

  @override
  State<NewRoomDialog> createState() => _NewRoomDialogState();
}

class _NewRoomDialogState extends State<NewRoomDialog> {
  final _name = TextEditingController();

  final _topic = TextEditingController();

  final _nameFocus = FocusNode();

  NewRoomViewModel get _viewModel => context.read<NewRoomViewModel>();

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BlocProvider.value(
      value: _viewModel.invites,
      child: BlocListener<JoinRoomViewModel, JoinRoomState>(
        listenWhen: (previous, current) =>
            previous.status != current.status &&
            current.status == JoinRoomStatus.success,
        listener: (context, state) =>
            Navigator.of(context).pop(JoinedRoom(state.roomId!)),
        child: BlocListener<NewRoomViewModel, NewRoomState>(
          listenWhen: (previous, current) =>
              previous.status != current.status &&
              current.status == NewRoomStatus.failure,
          // O campo só volta a aceitar foco depois do rebuild que o reabilita.
          listener: (context, state) =>
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _nameFocus.requestFocus();
              }),
          child: BlocConsumer<NewRoomViewModel, NewRoomState>(
            listenWhen: (previous, current) =>
                previous.status != current.status &&
                current.status == NewRoomStatus.success,
            listener: (context, state) =>
                Navigator.of(context).pop(state.created),
            builder: (context, state) {
              final joining = context.select(
                (JoinRoomViewModel viewModel) => viewModel.state.joining,
              );
              final busy = state.creating || joining;
              return PopScope(
                canPop: !busy,
                child: Dialog(
                  key: const Key('new_room_dialog'),
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
                        _Header(busy: busy),
                        _TabPicker(
                          tab: state.tab,
                          enabled: !busy,
                          onChanged: _viewModel.tabChanged,
                        ),
                        Flexible(
                          child: switch (state.tab) {
                            NewRoomTab.create => _CreateRoomForm(
                              state: state,
                              busy: busy,
                              viewModel: _viewModel,
                              name: _name,
                              nameFocus: _nameFocus,
                              topic: _topic,
                            ),
                            NewRoomTab.join => const JoinRoomForm(),
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CreateRoomForm extends StatelessWidget {
  const _CreateRoomForm({
    required this.state,
    required this.busy,
    required this.viewModel,
    required this.name,
    required this.nameFocus,
    required this.topic,
  });

  final NewRoomState state;

  final bool busy;

  final NewRoomViewModel viewModel;

  final TextEditingController name;

  final FocusNode nameFocus;

  final TextEditingController topic;

  @override
  Widget build(BuildContext context) {
    final invites = context.watch<InviteChipsViewModel>().state;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Opacity(
              opacity: busy ? 0.55 : 1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _NameField(
                      controller: name,
                      focusNode: nameFocus,
                      enabled: !busy,
                      onChanged: viewModel.nameChanged,
                      onSubmitted: viewModel.submit,
                    ),
                    const SizedBox(height: 16),
                    _TopicField(
                      controller: topic,
                      enabled: !busy,
                      onChanged: viewModel.topicChanged,
                    ),
                    const SizedBox(height: 16),
                    _VisibilityPicker(
                      isPublic: state.isPublic,
                      enabled: !busy,
                      onChanged: viewModel.visibilityChanged,
                    ),
                    if (!state.isPublic) ...[
                      const SizedBox(height: 14),
                      _ShareHistoryOption(
                        value: state.shareHistory,
                        enabled: !busy,
                        onChanged: viewModel.shareHistoryChanged,
                      ),
                    ],
                    const SizedBox(height: 16),
                    InviteChipsField(enabled: !busy),
                    if (state.status == NewRoomStatus.failure) ...[
                      const SizedBox(height: 16),
                      RoomDialogAlert(
                        key: const Key('new_room_error'),
                        title: 'Não foi possível criar a sala',
                        detail: _createFailureDetail(
                          state.failure,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        RoomDialogActions(
          submitKey: const Key('new_room_submit'),
          label: _createLabel(state),
          busy: state.creating,
          canSubmit: state.canSubmitWith(invites),
          onSubmit: viewModel.submit,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Nova sala',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          Tooltip(
            message: 'Fechar',
            child: InkWell(
              key: const Key('new_room_esc'),
              borderRadius: BorderRadius.circular(4),
              onTap: busy ? null : () => Navigator.of(context).maybePop(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.dialogBorder),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Esc',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabPicker extends StatelessWidget {
  const _TabPicker({
    required this.tab,
    required this.enabled,
    required this.onChanged,
  });

  final NewRoomTab tab;

  final bool enabled;

  final ValueChanged<NewRoomTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: colors.listBackground,
          border: Border.all(color: colors.dialogBorder),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            Expanded(
              child: _SegmentOption(
                key: const Key('new_room_tab_create'),
                label: 'Criar',
                selected: tab == NewRoomTab.create,
                onTap: enabled ? () => onChanged(NewRoomTab.create) : null,
              ),
            ),
            Expanded(
              child: _SegmentOption(
                key: const Key('new_room_tab_join'),
                label: 'Entrar',
                selected: tab == NewRoomTab.join,
                onTap: enabled ? () => onChanged(NewRoomTab.join) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;

  final bool enabled;

  final ValueChanged<String> onChanged;

  final FocusNode focusNode;

  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: colors.listBackground,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: focusNode.hasFocus ? colors.accent : colors.dialogBorder,
          ),
        ),
        child: Row(
          children: [
            Text('#', style: TextStyle(fontSize: 15, color: colors.textMuted)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const Key('new_room_name'),
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                enabled: enabled,
                onChanged: onChanged,
                onSubmitted: (_) => onSubmitted(),
                // Sem isto o Enter tira o foco mesmo quando não dá para criar.
                onEditingComplete: () {},
                textInputAction: TextInputAction.done,
                cursorColor: colors.accent,
                style: TextStyle(fontSize: 15, color: colors.textPrimary),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Nome da sala',
                  hintStyle: TextStyle(color: colors.textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicField extends StatelessWidget {
  const _TopicField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;

  final bool enabled;

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: color),
    );
    return TextField(
      key: const Key('new_room_topic'),
      controller: controller,
      enabled: enabled,
      minLines: 1,
      maxLines: 2,
      onChanged: onChanged,
      cursorColor: colors.accent,
      style: TextStyle(fontSize: 14, height: 1.45, color: colors.textPrimary),
      decoration: InputDecoration(
        isCollapsed: true,
        filled: true,
        fillColor: colors.listBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
        hintText: 'Tópico (opcional)',
        hintStyle: TextStyle(color: colors.textMuted),
        enabledBorder: border(colors.dialogBorder),
        disabledBorder: border(colors.dialogBorder),
        focusedBorder: border(colors.accent),
      ),
    );
  }
}

class _VisibilityPicker extends StatelessWidget {
  const _VisibilityPicker({
    required this.isPublic,
    required this.enabled,
    required this.onChanged,
  });

  final bool isPublic;

  final bool enabled;

  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: colors.listBackground,
            border: Border.all(color: colors.dialogBorder),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Expanded(
                child: _SegmentOption(
                  key: const Key('new_room_private'),
                  label: 'Privada',
                  selected: !isPublic,
                  onTap: enabled ? () => onChanged(false) : null,
                ),
              ),
              Expanded(
                child: _SegmentOption(
                  key: const Key('new_room_public'),
                  label: 'Pública',
                  selected: isPublic,
                  onTap: enabled ? () => onChanged(true) : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isPublic
              ? 'Entra quem tiver o link · sem cifra'
              : 'Só por convite · cifrada',
          style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _ShareHistoryOption extends StatelessWidget {
  const _ShareHistoryOption({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;

  final bool enabled;

  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled ? () => onChanged(!value) : null,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Novos membros veem as mensagens anteriores',
                  style: TextStyle(fontSize: 14, color: colors.textPrimary),
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                key: const Key('new_room_share_history'),
                value: value,
                onChanged: enabled ? onChanged : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                activeThumbColor: colors.onAccent,
                activeTrackColor: colors.accent,
                inactiveThumbColor: colors.textMuted,
                inactiveTrackColor: colors.listBackground,
                trackOutlineColor: WidgetStatePropertyAll(
                  value ? colors.accent : colors.dialogBorder,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Ao convidar, as chaves das mensagens anteriores vão junto. Para '
          'isso, esta sessão precisa estar verificada (chave de recuperação).',
          style: TextStyle(fontSize: 12.5, color: colors.textMuted),
        ),
      ],
    );
  }
}

class _SegmentOption extends StatelessWidget {
  const _SegmentOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;

  final bool selected;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.chip : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: selected ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

String _createFailureDetail(CreateRoomFailureType? failure) =>
    failure == CreateRoomFailureType.network
    ? 'Sem conexão com o servidor. Seus dados continuam aqui.'
    : 'Erro inesperado. Tente de novo.';

String _createLabel(NewRoomState state) => state.creating
    ? 'Criando…'
    : state.status == NewRoomStatus.failure
    ? 'Tentar de novo'
    : 'Criar sala';
