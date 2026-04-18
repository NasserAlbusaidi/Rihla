import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../shared/animations/fade_in_list.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/search_filter_bar.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../models/gear_item_model.dart';
import '../widgets/gear_add_input.dart';
import '../widgets/gear_hero_card.dart';
import '../widgets/gear_item_card.dart';

/// Filter + search + list + empty state for the gear packing list.
///
/// Stateless — all filter/search state is owned by GearScreen and passed
/// down as params. Callbacks lift state changes back to the screen.
class GearListView extends StatelessWidget {
  final List<GearItem> items;
  final String? currentUserId;
  final String searchQuery;
  final String? statusFilter;
  final bool hideClaimed;
  final void Function(GearItem item, bool isMine) onTogglePacked;
  final void Function(String action, GearItem item) onMenuAction;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onStatusFilterChanged;
  final VoidCallback onRefresh;

  // Hero card props
  final VoidCallback onAddItem;

  // Add-input props
  final TextEditingController addController;
  final bool isHighPriority;
  final ValueChanged<bool> onPriorityChanged;
  final VoidCallback onSubmitAdd;
  final FocusNode? addFocusNode;

  const GearListView({
    super.key,
    required this.items,
    required this.currentUserId,
    required this.searchQuery,
    required this.statusFilter,
    required this.hideClaimed,
    required this.onTogglePacked,
    required this.onMenuAction,
    required this.onSearchChanged,
    required this.onStatusFilterChanged,
    required this.onRefresh,
    required this.onAddItem,
    required this.addController,
    required this.isHighPriority,
    required this.onPriorityChanged,
    required this.onSubmitAdd,
    this.addFocusNode,
  });

  List<GearItem> _filtered() {
    return items.where((item) {
      if (searchQuery.isNotEmpty) {
        if (!item.itemName.toLowerCase().contains(searchQuery.toLowerCase())) {
          return false;
        }
      }
      if (statusFilter != null) {
        switch (statusFilter) {
          case 'Unclaimed':
            if (item.assignedTo != null) return false;
          case 'Claimed':
            if (item.assignedTo == null || item.isPacked) return false;
          case 'Packed':
            if (!item.isPacked) return false;
        }
      }
      if (hideClaimed && item.status != GearStatus.unclaimed) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final packedCount = items.where((i) => i.isPacked).length;
    final totalCount = items.length;
    final priorityCount =
        items.where((i) => i.isHighPriority && !i.isPacked).length;

    final filteredItems = _filtered();

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: GearHeroCard(
              packedCount: packedCount,
              totalCount: totalCount,
              priorityCount: priorityCount,
              onAddItem: onAddItem,
            ),
          ),
          SliverToBoxAdapter(
            child: SearchFilterBar(
              onSearchChanged: onSearchChanged,
              hintText: 'Search gear...',
              filters: const ['Unclaimed', 'Claimed', 'Packed'],
              activeFilter: statusFilter,
              onFilterChanged: onStatusFilterChanged,
            ),
          ),
          // Add item input — always shown regardless of list state
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: GearAddInput(
                controller: addController,
                isHighPriority: isHighPriority,
                onPriorityChanged: onPriorityChanged,
                onSubmit: onSubmitAdd,
                focusNode: addFocusNode,
              ),
            ),
          ),
          if (filteredItems.isEmpty && items.isNotEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'No items match your filter',
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            )
          else if (items.isEmpty)
            SliverFillRemaining(
              child: EmptyStateView(
                icon: Iconsax.bag_2,
                title: 'Nothing packed yet',
                message:
                    'Add gear items to track what everyone needs to bring.',
                actionLabel: 'Add Gear Item',
                onAction: onAddItem,
                accentGradient: LinearGradient(
                  colors: [
                    context.colors.moduleGear,
                    context.colors.moduleGearLight,
                  ],
                ),
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'GEAR ITEMS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: context.colors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverToBoxAdapter(
                child: FadeInList(
                  children: filteredItems.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GearItemCard(
                        item: item,
                        currentUserId: currentUserId,
                        onTogglePacked: onTogglePacked,
                        onMenuAction: onMenuAction,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
