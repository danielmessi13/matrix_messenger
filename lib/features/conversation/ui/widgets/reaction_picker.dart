import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme.dart';

const _pickerSize = Size(340, 400);

const _gap = 6.0;

class ReactionPickerButton extends StatefulWidget {
  const ReactionPickerButton({
    super.key,
    required this.onSelected,
    required this.alignEnd,
    required this.builder,
    this.onOpenChanged,
  });

  final ValueChanged<String> onSelected;

  final bool alignEnd;

  final Widget Function(BuildContext context, VoidCallback open) builder;

  final ValueChanged<bool>? onOpenChanged;

  @override
  State<ReactionPickerButton> createState() => _ReactionPickerButtonState();
}

class _ReactionPickerButtonState extends State<ReactionPickerButton> {
  final _link = LayerLink();

  final _portal = OverlayPortalController();

  bool _above = false;

  bool _isOpen = false;

  void _open() {
    final box = context.findRenderObject() as RenderBox?;
    final screen = MediaQuery.sizeOf(context).height;
    if (box != null) {
      final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      _above = bottom + _gap + _pickerSize.height > screen;
    }
    _isOpen = true;
    setState(_portal.show);
    widget.onOpenChanged?.call(true);
  }

  void _close() {
    if (!_isOpen) return;
    _isOpen = false;
    setState(_portal.hide);
    widget.onOpenChanged?.call(false);
  }

  @override
  void dispose() {
    // Quem escuta guarda "aberto"; sem o aviso esse estado ficaria preso.
    if (_isOpen) widget.onOpenChanged?.call(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final end = widget.alignEnd;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => Positioned(
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: switch ((_above, end)) {
            (true, true) => Alignment.topRight,
            (true, false) => Alignment.topLeft,
            (false, true) => Alignment.bottomRight,
            (false, false) => Alignment.bottomLeft,
          },
          followerAnchor: switch ((_above, end)) {
            (true, true) => Alignment.bottomRight,
            (true, false) => Alignment.bottomLeft,
            (false, true) => Alignment.topRight,
            (false, false) => Alignment.topLeft,
          },
          offset: Offset(0, _above ? -_gap : _gap),
          child: TapRegion(
            groupId: this,
            onTapOutside: (_) => _close(),
            child: _PickerCard(
              onSelected: (emoji) {
                _close();
                widget.onSelected(emoji);
              },
              onClose: _close,
            ),
          ),
        ),
      ),
      child: TapRegion(
        groupId: this,
        child: CompositedTransformTarget(
          link: _link,
          child: widget.builder(context, _open),
        ),
      ),
    );
  }
}

class _PickerCard extends StatelessWidget {
  const _PickerCard({required this.onSelected, required this.onClose});

  final ValueChanged<String> onSelected;

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
      child: Focus(
        autofocus: true,
        child: Material(
          key: const Key('reaction_picker'),
          type: MaterialType.transparency,
          child: Container(
            width: _pickerSize.width,
            height: _pickerSize.height,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.dialogBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x59000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: EmojiPicker(
              onEmojiSelected: (_, emoji) => onSelected(emoji.emoji),
              config: Config(
                height: _pickerSize.height,
                // A checagem de glifo só existe no Android; no desktop só atrasa a abertura.
                checkPlatformCompatibility: false,
                locale: const Locale('pt'),
                emojiViewConfig: EmojiViewConfig(
                  columns: 8,
                  emojiSizeMax: 26,
                  backgroundColor: colors.surfaceRaised,
                  noRecents: Text(
                    'Nenhum emoji recente',
                    style: TextStyle(fontSize: 13, color: colors.textMuted),
                  ),
                ),
                categoryViewConfig: CategoryViewConfig(
                  initCategory: Category.SMILEYS,
                  backgroundColor: colors.surfaceRaised,
                  indicatorColor: colors.accent,
                  iconColor: colors.textMuted,
                  iconColorSelected: colors.accent,
                  dividerColor: colors.border,
                ),
                bottomActionBarConfig: BottomActionBarConfig(
                  showBackspaceButton: false,
                  backgroundColor: colors.surfaceRaised,
                  buttonColor: colors.surfaceRaised,
                  buttonIconColor: colors.icon,
                ),
                searchViewConfig: SearchViewConfig(
                  backgroundColor: colors.surfaceRaised,
                  buttonIconColor: colors.icon,
                  hintText: 'Buscar emoji',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
