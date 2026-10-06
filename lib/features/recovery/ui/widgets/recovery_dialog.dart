import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../../domain/models/recovery_failure.dart';
import '../view_models/recovery_state.dart';
import '../view_models/recovery_view_model.dart';
import 'recovery_dialog_parts.dart';

Future<void> showRecoveryDialog(
  BuildContext context,
  RecoveryViewModel viewModel,
) async {
  await showDialog<void>(
    context: context,
    barrierColor: const Color(0xB8080706),
    builder: (_) => RecoveryDialog(viewModel: viewModel),
  );
  // Qualquer saída do sucesso (botão, Esc, clique fora) libera o cartão.
  if (!viewModel.isClosed && viewModel.state.submit == RecoverySubmit.success) {
    viewModel.finish();
  }
}

class RecoveryDialog extends StatefulWidget {
  const RecoveryDialog({super.key, required this.viewModel});

  final RecoveryViewModel viewModel;

  @override
  State<RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends State<RecoveryDialog> {
  // Fica aqui, não no campo: o texto precisa sobreviver ao estado 3 quando a chave falha.
  final _controller = TextEditingController();

  late final _focus = FocusNode(onKeyEvent: _onKey);

  // Também aqui, para não voltar a ocultar quando o diálogo troca de estado.
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    widget.viewModel.resetSubmit();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final enter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (event is! KeyDownEvent || !enter) return KeyEventResult.ignored;
    _submit();
    return KeyEventResult.handled;
  }

  void _submit() => widget.viewModel.recover(_controller.text);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RecoveryViewModel, RecoveryState>(
      bloc: widget.viewModel,
      buildWhen: (previous, current) =>
          previous.submit != current.submit ||
          previous.failure != current.failure,
      builder: (context, state) => PopScope(
        canPop: state.submit != RecoverySubmit.running,
        child: RecoveryDialogFrame(
          key: const Key('recovery_dialog'),
          child: switch (state.submit) {
            RecoverySubmit.idle || RecoverySubmit.failure => _KeyInput(
              controller: _controller,
              focusNode: _focus,
              failure: state.submit == RecoverySubmit.failure
                  ? state.failure ?? RecoveryFailureType.unknown
                  : null,
              revealed: _revealed,
              onToggleReveal: () => setState(() => _revealed = !_revealed),
              onChanged: widget.viewModel.resetSubmit,
              onSubmit: _submit,
            ),
            RecoverySubmit.running => const _Unlocking(),
            RecoverySubmit.success => const _Unlocked(),
          },
        ),
      ),
    );
  }
}

class _KeyInput extends StatelessWidget {
  const _KeyInput({
    required this.controller,
    required this.focusNode,
    required this.failure,
    required this.revealed,
    required this.onToggleReveal,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;

  final FocusNode focusNode;

  final RecoveryFailureType? failure;

  final bool revealed;

  final VoidCallback onToggleReveal;

  final VoidCallback onChanged;

  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: failure == null ? colors.accent : colors.danger,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const RecoveryDialogHeading(
          title: 'Digite sua chave de recuperação',
          body:
              'Você recebeu essa chave (ou frase de segurança) ao ativar a '
              'criptografia.',
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('recovery_key'),
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          maxLines: 1,
          obscureText: !revealed,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => onChanged(),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 15,
            height: 1.6,
            color: colors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'EsTR mwqJ JoNW …',
            hintStyle: TextStyle(color: colors.textMuted),
            suffixIcon: IconButton(
              key: const Key('recovery_toggle_visibility'),
              tooltip: revealed ? 'Ocultar chave' : 'Mostrar chave',
              color: colors.textSecondary,
              icon: Icon(
                revealed
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: onToggleReveal,
            ),
            filled: true,
            fillColor: colors.background,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: border,
          ),
        ),
        if (failure case final failure?) ...[
          const SizedBox(height: 6),
          Text(
            failure.message,
            key: const Key('recovery_error'),
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: colors.dangerText,
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            RecoverySecondaryButton(
              label: 'Cancelar',
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 10),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => RecoveryPrimaryButton(
                key: const Key('recovery_submit'),
                label: 'Desbloquear',
                onPressed: value.text.trim().isEmpty ? null : onSubmit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Unlocking extends StatelessWidget {
  const _Unlocking();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecoveryDialogHeading(
          title: 'Desbloqueando mensagens',
          body: 'Leva alguns segundos. Não feche o app.',
        ),
        SizedBox(height: 20),
        RecoveryProgressBar(key: Key('recovery_progress')),
      ],
    );
  }
}

class _Unlocked extends StatelessWidget {
  const _Unlocked();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.accent.withValues(alpha: 0.16),
          ),
          child: Text(
            '✓',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colors.accentHighlight,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const RecoveryDialogHeading(
          title: 'Mensagens desbloqueadas',
          body: 'Mensagens antigas já podem ser lidas nesta sessão.',
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: RecoveryPrimaryButton(
            key: const Key('recovery_finish'),
            label: 'Voltar às conversas',
            onPressed: () => Navigator.of(context).pop(),
            autofocus: true,
          ),
        ),
      ],
    );
  }
}

extension on RecoveryFailureType {
  String get message => switch (this) {
    RecoveryFailureType.invalidKey =>
      'Essa chave não confere. Confira se copiou todos os grupos.',
    RecoveryFailureType.network =>
      'Não foi possível falar com o servidor. Tente de novo.',
    RecoveryFailureType.backupExists ||
    RecoveryFailureType.authRequired ||
    RecoveryFailureType.unknown => 'Não foi possível desbloquear as mensagens.',
  };
}
