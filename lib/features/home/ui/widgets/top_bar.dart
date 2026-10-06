import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.newRoomButton,
    required this.searchField,
    required this.userMenu,
  });

  final Widget newRoomButton;

  final Widget searchField;

  final Widget userMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 68,
      padding: const EdgeInsets.only(right: 28),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 24),
          Image.asset('assets/icon/icon.png', width: 36, height: 36),
          const SizedBox(width: 12),
          Text(
            'prosa',
            style: TextStyle(
              fontFamily: AppFonts.serif,
              fontSize: 26,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(width: 24),
          newRoomButton,
          const SizedBox(width: 24),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: searchField,
              ),
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 200,
            child: Align(alignment: Alignment.centerRight, child: userMenu),
          ),
        ],
      ),
    );
  }
}
