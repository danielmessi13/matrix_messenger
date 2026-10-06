import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../view_models/recovery_state.dart';
import '../view_models/recovery_view_model.dart';
import 'recovery_dialog.dart';
import 'setup_recovery_dialog.dart';

class RecoveryCard extends StatelessWidget {
  const RecoveryCard({super.key, required this.viewModel});

  final RecoveryViewModel viewModel;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<RecoveryViewModel, RecoveryState>(
        bloc: viewModel,
        buildWhen: (previous, current) => previous.card != current.card,
        builder: (context, state) {
          final kind = state.card;
          if (kind == RecoveryCardKind.none) return const SizedBox.shrink();
          final (title, body, label, buttonKey) = switch (kind) {
            RecoveryCardKind.setup => (
              'Proteja suas mensagens',
              'Sem uma chave de recuperação, sair da conta apaga o acesso às '
                  'conversas criptografadas.',
              'Configurar recuperação',
              const Key('recovery_setup_open'),
            ),
            RecoveryCardKind.unlock || RecoveryCardKind.none => (
              'Mensagens antigas trancadas',
              'Esta sessão ainda não tem sua chave de recuperação. '
                  'Até configurar, conversas criptografadas aparecem '
                  'fechadas.',
              'Configurar agora',
              const Key('recovery_open'),
            ),
          };
          final colors = context.colors;
          return Padding(
            key: const Key('recovery_card'),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.hoverRow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colors.warning.withValues(alpha: 0.4),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colors.warning,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.warningText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 36,
                      child: TextButton(
                        key: buttonKey,
                        onPressed: () => kind == RecoveryCardKind.setup
                            ? showSetupRecoveryDialog(context)
                            : showRecoveryDialog(context, viewModel),
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.hovered)
                                ? colors.borderStrong
                                : colors.surfaceHigh,
                          ),
                          foregroundColor: WidgetStatePropertyAll(
                            colors.textPrimary,
                          ),
                          overlayColor: const WidgetStatePropertyAll(
                            Colors.transparent,
                          ),
                          shape: WidgetStatePropertyAll(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          textStyle: const WidgetStatePropertyAll(
                            TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        child: Text(label),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
