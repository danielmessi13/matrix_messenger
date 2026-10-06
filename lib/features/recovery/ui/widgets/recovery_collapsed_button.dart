import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../view_models/recovery_state.dart';
import '../view_models/recovery_view_model.dart';

class RecoveryCollapsedButton extends StatelessWidget {
  const RecoveryCollapsedButton({
    super.key,
    required this.viewModel,
    required this.onPressed,
  });

  final RecoveryViewModel viewModel;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<RecoveryViewModel, RecoveryState>(
        bloc: viewModel,
        buildWhen: (previous, current) => previous.card != current.card,
        builder: (context, state) {
          if (state.card == RecoveryCardKind.none) {
            return const SizedBox.shrink();
          }
          final colors = context.colors;
          return Column(
            key: const Key('recovery_collapsed'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: state.card == RecoveryCardKind.setup
                    ? 'Mensagens sem backup · configure a recuperação'
                    : 'Mensagens antigas trancadas · configure a chave de '
                          'recuperação',
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onPressed,
                    borderRadius: BorderRadius.circular(12),
                    hoverColor: colors.warning.withValues(alpha: 0.08),
                    child: Ink(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.warning.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colors.warning.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '!',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colors.warningText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(width: 28, height: 1, color: colors.border),
            ],
          );
        },
      );
}
