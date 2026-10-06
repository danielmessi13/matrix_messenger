import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/ui/animated_pane.dart';
import '../../../../../core/ui/pane_toggle_button.dart';
import '../../../domain/models/room_filter.dart';
import 'room_labels.dart';

const kFilterRailWidth = 250.0;

const kFilterRailCompactWidth = 88.0;

class FilterRail extends StatelessWidget {
  const FilterRail({
    super.key,
    required this.expanded,
    required this.selected,
    required this.unreadByFilter,
    required this.onSelect,
    required this.onToggle,
  });

  final bool expanded;

  final RoomFilter selected;

  final Map<RoomFilter, int> unreadByFilter;

  final ValueChanged<RoomFilter> onSelect;

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => AnimatedPane(
    expanded: expanded,
    expandedWidth: kFilterRailWidth,
    compactWidth: kFilterRailCompactWidth,
    decoration: BoxDecoration(
      border: Border(right: BorderSide(color: context.colors.border)),
    ),
    expandedChild: _RailContent(
      expanded: true,
      selected: selected,
      unreadByFilter: unreadByFilter,
      onSelect: onSelect,
      onToggle: onToggle,
    ),
    compactChild: _RailContent(
      expanded: false,
      selected: selected,
      unreadByFilter: unreadByFilter,
      onSelect: onSelect,
      onToggle: onToggle,
    ),
  );
}

class _RailContent extends StatelessWidget {
  const _RailContent({
    required this.expanded,
    required this.selected,
    required this.unreadByFilter,
    required this.onSelect,
    required this.onToggle,
  });

  final bool expanded;

  final RoomFilter selected;

  final Map<RoomFilter, int> unreadByFilter;

  final ValueChanged<RoomFilter> onSelect;

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: expanded
          ? const EdgeInsets.all(20)
          : const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 0, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'FILTROS',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                  PaneToggleButton(
                    key: const Key('toggle_filters'),
                    pointsLeft: true,
                    tooltip: 'Minimizar filtros',
                    onPressed: onToggle,
                    size: 26,
                  ),
                ],
              ),
            ),
          for (final filter in RoomFilter.values)
            _FilterItem(
              filter: filter,
              expanded: expanded,
              selected: filter == selected,
              unread: unreadByFilter[filter] ?? 0,
              onTap: () => onSelect(filter),
            ),
          const Spacer(),
          if (!expanded)
            Center(
              child: PaneToggleButton(
                key: const Key('toggle_filters'),
                pointsLeft: false,
                tooltip: 'Expandir filtros',
                onPressed: onToggle,
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterItem extends StatelessWidget {
  const _FilterItem({
    required this.filter,
    required this.expanded,
    required this.selected,
    required this.unread,
    required this.onTap,
  });

  final RoomFilter filter;

  final bool expanded;

  final bool selected;

  final int unread;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final item = Material(
      color: selected ? colors.activeFilter : Colors.transparent,
      borderRadius: BorderRadius.circular(expanded ? 6 : 10),
      child: InkWell(
        key: Key('filter_${filter.name}'),
        onTap: onTap,
        hoverColor: colors.surface,
        borderRadius: BorderRadius.circular(expanded ? 6 : 10),
        child: expanded
            ? _WideFilterItem(filter: filter, unread: unread)
            : _CompactFilterItem(filter: filter, unread: unread),
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2, horizontal: expanded ? 0 : 8),
      child: item,
    );
  }
}

class _WideFilterItem extends StatelessWidget {
  const _WideFilterItem({required this.filter, required this.unread});

  final RoomFilter filter;

  final int unread;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Icon(filter.icon, size: 18, color: colors.icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              filter.title,
              style: TextStyle(fontSize: 14.5, color: colors.textPrimary),
            ),
          ),
          if (unread > 0)
            Text('$unread', style: TextStyle(color: colors.textMuted)),
        ],
      ),
    );
  }
}

class _CompactFilterItem extends StatelessWidget {
  const _CompactFilterItem({required this.filter, required this.unread});

  final RoomFilter filter;

  final int unread;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                Icon(filter.icon, size: 22, color: colors.icon),
                const SizedBox(height: 5),
                Text(
                  filter.shortTitle,
                  style: TextStyle(fontSize: 11.5, color: colors.textPrimary),
                ),
              ],
            ),
          ),
        ),
        if (unread > 0)
          Positioned(
            right: 10,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$unread',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: colors.background,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
