import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/models/recovery_failure.dart';
import '../view_models/recovery_state.dart';
import '../view_models/recovery_view_model.dart';

class RecoveryBanner extends StatelessWidget {
  const RecoveryBanner({super.key, required this.viewModel});

  final RecoveryViewModel viewModel;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<RecoveryViewModel, RecoveryState>(
        bloc: viewModel,
        buildWhen: (previous, current) =>
            previous.showBanner != current.showBanner,
        builder: (context, state) {
          if (!state.showBanner) return const SizedBox.shrink();
          return MaterialBanner(
            key: const Key('recovery_banner'),
            leading: const Icon(Icons.lock_outline),
            content: const Text(
              'Mensagens cifradas anteriores a este login não podem ser lidas '
              'neste dispositivo. Use sua chave de recuperação para '
              'recuperar o histórico.',
            ),
            actions: [
              TextButton(
                onPressed: viewModel.dismiss,
                child: const Text('Agora não'),
              ),
              TextButton(
                key: const Key('recovery_open'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _RecoveryDialog(viewModel: viewModel),
                ),
                child: const Text('Recuperar histórico'),
              ),
            ],
          );
        },
      );
}

class _RecoveryDialog extends StatefulWidget {
  const _RecoveryDialog({required this.viewModel});

  final RecoveryViewModel viewModel;

  @override
  State<_RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends State<_RecoveryDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.viewModel.resetSubmit();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => widget.viewModel.recover(_controller.text);

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<RecoveryViewModel, RecoveryState>(
        bloc: widget.viewModel,
        listenWhen: (previous, current) => previous.submit != current.submit,
        listener: (context, state) {
          if (state.submit == RecoverySubmit.success) {
            Navigator.of(context).pop();
          }
        },
        builder: (context, state) {
          final running = state.submit == RecoverySubmit.running;
          return AlertDialog(
            key: const Key('recovery_dialog'),
            title: const Text('Recuperar histórico'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Digite a chave de recuperação (ou a frase de segurança) '
                    'configurada em outro app, como o Element.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('recovery_key'),
                    controller: _controller,
                    enabled: !running,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Chave de recuperação',
                      hintText: 'EsTx ABCD ...',
                      prefixIcon: const Icon(Icons.key_outlined),
                      errorText: state.submit == RecoverySubmit.failure
                          ? state.failure?.message
                          : null,
                      errorMaxLines: 2,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: running ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                key: const Key('recovery_submit'),
                onPressed: running ? null : _submit,
                child: running
                    ? const _ButtonSpinner()
                    : const Text('Recuperar'),
              ),
            ],
          );
        },
      );
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 20,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

extension on RecoveryFailureType {
  String get message => switch (this) {
    RecoveryFailureType.invalidKey => 'Chave de recuperação inválida.',
    RecoveryFailureType.network =>
      'Não foi possível falar com o servidor. Tente de novo.',
    RecoveryFailureType.unknown => 'Não foi possível recuperar o histórico.',
  };
}
