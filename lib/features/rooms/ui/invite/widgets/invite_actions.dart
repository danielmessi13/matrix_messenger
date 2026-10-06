import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../app/theme.dart';
import '../view_models/invite_state.dart';
import '../view_models/invite_view_model.dart';

class InviteActions extends StatelessWidget {
  const InviteActions({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<InviteViewModel>();
    final colors = context.colors;
    return BlocBuilder<InviteViewModel, InviteState>(
      builder: (context, state) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Você foi convidado para esta sala.',
            style: TextStyle(
              fontFamily: AppFonts.serif,
              fontStyle: FontStyle.italic,
              fontSize: 17,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                key: const Key('invite_decline'),
                onPressed: state.isRunning ? null : viewModel.decline,
                child: state.status == InviteStatus.declining
                    ? const _ButtonSpinner()
                    : const Text('Recusar'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                key: const Key('invite_accept'),
                onPressed: state.isRunning ? null : viewModel.accept,
                child: state.status == InviteStatus.accepting
                    ? const _ButtonSpinner()
                    : const Text('Aceitar'),
              ),
            ],
          ),
          if (state.status == InviteStatus.failure) ...[
            const SizedBox(height: 12),
            Text(
              'Não foi possível responder ao convite.',
              key: const Key('invite_failure'),
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 16,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
