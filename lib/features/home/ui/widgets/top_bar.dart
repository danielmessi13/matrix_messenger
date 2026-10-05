import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.searchField, required this.userMenu});

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
          SizedBox(
            width: 88,
            child: Text(
              'Ó',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.serif,
                fontSize: 26,
                color: colors.textPrimary,
              ),
            ),
          ),
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
            width: 160,
            child: Align(alignment: Alignment.centerRight, child: userMenu),
          ),
        ],
      ),
    );
  }
}
