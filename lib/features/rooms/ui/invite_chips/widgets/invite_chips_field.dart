import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../app/theme.dart';
import '../view_models/invite_chips_state.dart';
import '../view_models/invite_chips_view_model.dart';

class InviteChipsField extends StatefulWidget {
  const InviteChipsField({
    super.key,
    this.enabled = true,
    this.autofocus = false,
    this.fieldKey = const Key('new_room_invite'),
    this.helpKey = const Key('new_room_invite_help'),
    this.chipKeyPrefix = 'new_room_chip',
    this.hintText = 'Convidar: @usuario:servidor',
    this.helpText =
        'Convidar (opcional): digite @usuario:servidor e aperte Enter.',
  });

  final bool enabled;

  final bool autofocus;

  final Key fieldKey;

  final Key helpKey;

  // Chips ganham as keys '<prefixo>_<id>' e '<prefixo>_remove_<id>'.
  final String chipKeyPrefix;

  final String hintText;

  final String helpText;

  @override
  State<InviteChipsField> createState() => _InviteChipsFieldState();
}

class _InviteChipsFieldState extends State<InviteChipsField> {
  late final _controller = TextEditingController(text: _viewModel.state.query);

  late final _focusNode = FocusNode(onKeyEvent: _onKey);

  InviteChipsViewModel get _viewModel => context.read<InviteChipsViewModel>();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controller.text.isEmpty) {
      _viewModel.editLastInvite();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _submit() {
    unawaited(_viewModel.addInvite());
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BlocConsumer<InviteChipsViewModel, InviteChipsState>(
      // O view model esvazia o campo ao virar chip; o controller acompanha.
      listener: (context, state) {
        if (_controller.text != state.query) {
          _controller.value = TextEditingValue(
            text: state.query,
            selection: TextSelection.collapsed(offset: state.query.length),
          );
        }
      },
      builder: (context, state) {
        final borderColor = state.hasError
            ? colors.danger
            : state.hasUnknown
            ? colors.warning
            : colors.dialogBorder;
        final helpColor = state.hasError
            ? colors.dangerText
            : state.hasUnknown
            ? colors.warningText
            : colors.textMuted;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: _focusNode.requestFocus,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                alignment: Alignment.centerLeft,
                // Sem chips, o texto alinha com o dos outros campos.
                padding: EdgeInsets.symmetric(
                  horizontal: state.chips.isEmpty ? 14 : 8,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: colors.listBackground,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: borderColor),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final (index, chip) in state.chips.indexed)
                      _Chip(
                        chip: chip,
                        keyPrefix: widget.chipKeyPrefix,
                        enabled: widget.enabled,
                        onRemove: () => _viewModel.removeInvite(index),
                      ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 160),
                      child: IntrinsicWidth(
                        child: TextField(
                          key: widget.fieldKey,
                          controller: _controller,
                          focusNode: _focusNode,
                          autofocus: widget.autofocus,
                          enabled: widget.enabled,
                          onChanged: _viewModel.queryChanged,
                          onSubmitted: (_) => _submit(),
                          textInputAction: TextInputAction.done,
                          cursorColor: colors.accent,
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: state.chips.isEmpty
                                ? widget.hintText
                                : null,
                            hintStyle: TextStyle(color: colors.textMuted),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _inviteHelp(state, widget.helpText),
              key: widget.helpKey,
              style: TextStyle(fontSize: 12.5, color: helpColor),
            ),
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.chip,
    required this.keyPrefix,
    required this.enabled,
    required this.onRemove,
  });

  final InviteChip chip;

  final String keyPrefix;

  final bool enabled;

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isError = chip.isError;
    final isUnknown = chip.status == InviteChipStatus.unknown;
    final textColor = isError
        ? colors.dangerText
        : isUnknown
        ? colors.warningText
        : colors.textPrimary;
    final removeColor = isError || isUnknown ? textColor : colors.textMuted;
    final border = isError
        ? Border.all(color: colors.danger)
        : isUnknown
        ? Border.all(color: colors.warning)
        : null;
    final body = Tooltip(
      message: _chipTooltip(chip),
      child: Container(
        key: Key('${keyPrefix}_${chip.id}'),
        height: 28,
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          color: isError ? colors.dangerSurface : colors.chip,
          border: border,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                chip.id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: textColor),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              key: Key('${keyPrefix}_remove_${chip.id}'),
              customBorder: const CircleBorder(),
              onTap: enabled ? onRemove : null,
              child: SizedBox(
                width: 20,
                height: 20,
                child: Center(
                  child: Text(
                    '×',
                    style: TextStyle(fontSize: 13, color: removeColor),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return chip.status == InviteChipStatus.checking
        ? Opacity(opacity: 0.55, child: body)
        : body;
  }
}

String _quoted(List<String> ids) => ids.map((id) => '“$id”').join(', ');

String _inviteHelp(InviteChipsState state, String neutral) {
  final format = state.invalidFormatIds;
  if (format.isNotEmpty) {
    final verb = format.length > 1 ? 'não estão' : 'não está';
    return '${_quoted(format)} $verb no formato @usuario:servidor.';
  }
  final missing = state.notFoundIds;
  if (missing.isNotEmpty) {
    final verb = missing.length > 1 ? 'não existem' : 'não existe';
    return '${_quoted(missing)} $verb no servidor.';
  }
  final unknown = state.unknownIds;
  if (unknown.isNotEmpty) {
    return 'Não foi possível verificar ${_quoted(unknown)}. '
        'O convite será enviado mesmo assim.';
  }
  return neutral;
}

// O ID completo vai junto: no chip ele pode estar cortado com reticências.
String _chipTooltip(InviteChip chip) {
  final detail = switch (chip.status) {
    InviteChipStatus.checking => 'Verificando…',
    InviteChipStatus.found => chip.displayName,
    InviteChipStatus.unknown => 'Não foi possível verificar',
    InviteChipStatus.invalidFormat => 'Use o formato @usuario:servidor',
    InviteChipStatus.notFound => 'Usuário não encontrado',
  };
  return detail == null ? chip.id : '${chip.id}\n$detail';
}
