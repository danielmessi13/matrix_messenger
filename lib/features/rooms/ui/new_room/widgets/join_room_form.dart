import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../app/theme.dart';
import '../../../domain/models/join_room_failure.dart';
import '../view_models/join_room_state.dart';
import '../view_models/join_room_view_model.dart';
import 'room_dialog_parts.dart';

class JoinRoomForm extends StatefulWidget {
  const JoinRoomForm({super.key});

  @override
  State<JoinRoomForm> createState() => _JoinRoomFormState();
}

class _JoinRoomFormState extends State<JoinRoomForm> {
  // O texto vive no view model; ao voltar para a aba o campo é refeito com ele.
  late final _controller = TextEditingController(
    text: context.read<JoinRoomViewModel>().state.target,
  );

  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<JoinRoomViewModel>();
    return BlocConsumer<JoinRoomViewModel, JoinRoomState>(
      listenWhen: (previous, current) =>
          previous.status != current.status &&
          current.status == JoinRoomStatus.failure,
      // O campo só volta a aceitar foco depois do rebuild que o reabilita.
      listener: (context, state) =>
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _focus.requestFocus();
          }),
      builder: (context, state) {
        final colors = context.colors;
        final busy = state.joining;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Opacity(
                  opacity: busy ? 0.55 : 1,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TargetField(
                          controller: _controller,
                          focusNode: _focus,
                          enabled: !busy,
                          onChanged: viewModel.targetChanged,
                          onSubmitted: viewModel.submit,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Cole um link matrix.to, um ID (!…) ou um endereço (#…).',
                          key: const Key('join_room_help'),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.textMuted,
                          ),
                        ),
                        if (state.status == JoinRoomStatus.failure) ...[
                          const SizedBox(height: 16),
                          RoomDialogAlert(
                            key: const Key('join_room_error'),
                            title: 'Não foi possível entrar na sala',
                            detail: _joinFailureDetail(state.failure),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            RoomDialogActions(
              submitKey: const Key('join_room_submit'),
              label: busy
                  ? 'Entrando…'
                  : state.status == JoinRoomStatus.failure
                  ? 'Tentar de novo'
                  : 'Entrar',
              busy: busy,
              canSubmit: state.canSubmit,
              onSubmit: viewModel.submit,
            ),
          ],
        );
      },
    );
  }
}

class _TargetField extends StatelessWidget {
  const _TargetField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;

  final FocusNode focusNode;

  final bool enabled;

  final ValueChanged<String> onChanged;

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
            Icon(Icons.link, size: 16, color: colors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const Key('join_room_target'),
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                enabled: enabled,
                onChanged: onChanged,
                onSubmitted: (_) => onSubmitted(),
                // Sem isto o Enter tira o foco mesmo quando não dá para entrar.
                onEditingComplete: () {},
                textInputAction: TextInputAction.done,
                cursorColor: colors.accent,
                style: TextStyle(fontSize: 15, color: colors.textPrimary),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Link, ID ou endereço da sala',
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

String _joinFailureDetail(JoinRoomFailureType? failure) => switch (failure) {
  JoinRoomFailureType.invalidLink => 'Isso não parece um link de sala. Use um link matrix.to, um ID (!…) ou um endereço (#…).',
  JoinRoomFailureType.notFound => 'Sala não encontrada.',
  JoinRoomFailureType.forbidden => 'Essa sala só aceita quem foi convidado.',
  JoinRoomFailureType.network =>
    'Sem conexão com o servidor. Seus dados continuam aqui.',
  JoinRoomFailureType.unknown || null => 'Erro inesperado. Tente de novo.',
};
