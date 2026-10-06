import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../../data/repositories/recovery_repository.dart';
import '../../domain/models/recovery_failure.dart';
import '../view_models/setup_recovery_state.dart';
import '../view_models/setup_recovery_view_model.dart';
import 'recovery_dialog_parts.dart';

// O ViewModel nasce e morre com o modal: a chave não fica na memória depois.
Future<void> showSetupRecoveryDialog(BuildContext context) async {
  final viewModel = SetupRecoveryViewModel(context.read<RecoveryRepository>());
  await showDialog<void>(
    context: context,
    barrierColor: const Color(0xB8080706),
    builder: (_) => SetupRecoveryDialog(viewModel: viewModel),
  );
  await viewModel.close();
}

class SetupRecoveryDialog extends StatelessWidget {
  const SetupRecoveryDialog({super.key, required this.viewModel});

  final SetupRecoveryViewModel viewModel;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<SetupRecoveryViewModel, SetupRecoveryState>(
        bloc: viewModel,
        builder: (context, state) => PopScope(
          canPop: state.canClose,
          child: RecoveryDialogFrame(
            key: const Key('setup_recovery_dialog'),
            child: switch (state.step) {
              SetupRecoveryStep.intro => _Intro(onCreate: viewModel.create),
              SetupRecoveryStep.creating => const _Creating(),
              SetupRecoveryStep.ready => _KeyReady(
                recoveryKey: state.recoveryKey ?? '',
                confirmed: state.confirmed,
                onConfirmed: viewModel.setConfirmed,
              ),
              SetupRecoveryStep.failure => _Failure(
                failure: state.failure ?? RecoveryFailureType.unknown,
                onRetry: viewModel.create,
              ),
            },
          ),
        ),
      );
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const RecoveryDialogHeading(
          title: 'Configurar recuperação',
          body:
              'O app vai criar um backup criptografado das suas chaves e uma '
              'chave de recuperação que só você tem. Com ela, você lê as '
              'mensagens antigas ao entrar de novo.',
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            RecoverySecondaryButton(
              label: 'Cancelar',
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 10),
            RecoveryPrimaryButton(
              key: const Key('setup_recovery_create'),
              label: 'Gerar chave',
              onPressed: onCreate,
              autofocus: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _Creating extends StatelessWidget {
  const _Creating();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecoveryDialogHeading(
          title: 'Criando o backup',
          body: 'Enviando suas chaves. Não feche o app.',
        ),
        SizedBox(height: 20),
        RecoveryProgressBar(key: Key('setup_recovery_progress')),
      ],
    );
  }
}

class _KeyReady extends StatefulWidget {
  const _KeyReady({
    required this.recoveryKey,
    required this.confirmed,
    required this.onConfirmed,
  });

  final String recoveryKey;

  final bool confirmed;

  final ValueChanged<bool> onConfirmed;

  @override
  State<_KeyReady> createState() => _KeyReadyState();
}

class _KeyReadyState extends State<_KeyReady> {
  bool _copied = false;

  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.recoveryKey));
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const RecoveryDialogHeading(
          title: 'Guarde sua chave de recuperação',
          body:
              'Ela não aparece de novo. Sem ela, mensagens antigas ficam '
              'ilegíveis em outro login.',
        ),
        const SizedBox(height: 20),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: SelectableText(
              widget.recoveryKey,
              key: const Key('setup_recovery_key'),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 15,
                height: 1.6,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: RecoverySecondaryButton(
            key: const Key('setup_recovery_copy'),
            label: _copied ? 'Copiada' : 'Copiar',
            onPressed: _copy,
          ),
        ),
        const SizedBox(height: 20),
        InkWell(
          onTap: () => widget.onConfirmed(!widget.confirmed),
          child: Row(
            children: [
              Checkbox(
                key: const Key('setup_recovery_confirm'),
                value: widget.confirmed,
                onChanged: (value) => widget.onConfirmed(value ?? false),
                activeColor: colors.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Guardei minha chave em um lugar seguro',
                  style: TextStyle(fontSize: 14, color: colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: RecoveryPrimaryButton(
            key: const Key('setup_recovery_finish'),
            label: 'Concluir',
            onPressed: widget.confirmed
                ? () => Navigator.of(context).pop()
                : null,
          ),
        ),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.failure, required this.onRetry});

  final RecoveryFailureType failure;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecoveryDialogHeading(
          title: 'Não deu certo',
          body: failure.setupMessage,
          bodyColor: context.colors.dangerText,
          bodyKey: const Key('setup_recovery_error'),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            RecoverySecondaryButton(
              label: 'Fechar',
              onPressed: () => Navigator.of(context).pop(),
            ),
            if (failure.canRetry) ...[
              const SizedBox(width: 10),
              RecoveryPrimaryButton(
                key: const Key('setup_recovery_retry'),
                label: 'Tentar de novo',
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

extension on RecoveryFailureType {
  String get setupMessage => switch (this) {
    RecoveryFailureType.network => 'Sem conexão com o servidor. Tente de novo.',
    RecoveryFailureType.authRequired =>
      'Seu servidor pediu a senha para ativar a verificação, e o app ainda '
          'não faz esse pedido.',
    RecoveryFailureType.backupExists =>
      'Esta conta já tem um backup criado por outro aplicativo. Configure a '
          'recuperação por ele.',
    RecoveryFailureType.invalidKey ||
    RecoveryFailureType.unknown => 'Não foi possível configurar a recuperação.',
  };

  // Repetir não muda a resposta do servidor nesses dois casos.
  bool get canRetry => switch (this) {
    RecoveryFailureType.authRequired ||
    RecoveryFailureType.backupExists => false,
    RecoveryFailureType.network ||
    RecoveryFailureType.invalidKey ||
    RecoveryFailureType.unknown => true,
  };
}
