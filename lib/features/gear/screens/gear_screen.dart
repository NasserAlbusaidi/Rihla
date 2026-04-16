import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/types/event_ref.dart';
import '../../../shared/animations/fade_in_list.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/search_filter_bar.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../auth/providers/auth_provider.dart';
import '../../events/providers/event_provider.dart';
import '../keys/gear_keys.dart';
import '../models/gear_item_model.dart';
import '../providers/gear_provider.dart';
import '../widgets/gear_hero_card.dart';
import '../widgets/gear_item_card.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../shared/widgets/offline_banner.dart';

/// Gear Screen — unified module template (D-08).
///
/// Layout: dark ModuleHeader → GearHeroCard → SearchFilterBar → gear item list.
/// Loading: SkeletonLoader. Empty: EmptyStateView with olive earthy gradient.
class GearScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String eventId;

  const GearScreen({
    super.key,
    required this.groupId,
    required this.eventId,
  });

  @override
  ConsumerState<GearScreen> createState() => _GearScreenState();
}

class _GearScreenState extends ConsumerState<GearScreen> {
  final _itemController = TextEditingController();
  bool _hideClaimed = false;
  bool _isHighPriority = false;
  String _searchQuery = '';
  String? _statusFilter;

  EventRef get _eventRef =>
      (groupId: widget.groupId, eventId: widget.eventId);

  @override
  void dispose() {
    _itemController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
    final eventAsync = ref.watch(eventDetailProvider(eventRef));
    final gearAsync = ref.watch(eventGearItemsProvider(eventRef));
    final currentUserId = ref.watch(currentUserProvider)?.uid;

    // Loading state — use skeleton instead of spinner
    if (eventAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppColorTokens.light.scaffoldBackground,
        body: Column(
          children: [
            const ModuleHeader(title: 'Gear', useDarkTheme: true),
            Expanded(child: SkeletonLoader.gearList()),
          ],
        ),
      );
    }

    final event = eventAsync.valueOrNull;

    // Not-found state per D-11
    if (event == null) {
      return Scaffold(
        backgroundColor: AppColorTokens.light.scaffoldBackground,
        body: Column(
          children: [
            const ModuleHeader(title: 'Not Found', useDarkTheme: true),
            Expanded(
              child: EmptyStateView(
                icon: Iconsax.warning_2,
                title: 'This event no longer exists',
                message:
                    'It may have been deleted. Tap below to go back to your groups.',
                actionLabel: 'Go Home',
                onAction: () => context.go('/home'),
                iconColor: AppColorTokens.light.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      key: GearKeys.screen,
      backgroundColor: AppColorTokens.light.scaffoldBackground,
      body: Column(
        children: [
          ModuleHeader(
            title: 'Gear',
            subtitle: event.name.toUpperCase(),
            useDarkTheme: true,
          ),
          const OfflineBanner(),
          Expanded(
            child: gearAsync.when(
              data: (items) => _buildContent(items, currentUserId),
              loading: SkeletonLoader.gearList,
              error: (e, st) {
                return _buildErrorState(e.toString());
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingAction(),
    );
  }

  Widget _buildContent(List<GearItem> items, String? currentUserId) {
    final packedCount = items.where((i) => i.isPacked).length;
    final totalCount = items.length;
    final priorityCount =
        items.where((i) => i.isHighPriority && !i.isPacked).length;

    final filteredItems = items.where((item) {
      if (_searchQuery.isNotEmpty) {
        if (!item.itemName.toLowerCase().contains(_searchQuery.toLowerCase())) {
          return false;
        }
      }
      if (_statusFilter != null) {
        switch (_statusFilter) {
          case 'Unclaimed':
            if (item.assignedTo != null) return false;
          case 'Claimed':
            if (item.assignedTo == null || item.isPacked) return false;
          case 'Packed':
            if (!item.isPacked) return false;
        }
      }
      if (_hideClaimed && item.status != GearStatus.unclaimed) return false;
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(eventGearItemsProvider(_eventRef));
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: GearHeroCard(
              packedCount: packedCount,
              totalCount: totalCount,
              priorityCount: priorityCount,
              onAddItem: _focusAddField,
            ),
          ),
          SliverToBoxAdapter(
            child: SearchFilterBar(
              onSearchChanged: (q) => setState(() => _searchQuery = q),
              hintText: 'Search gear...',
              filters: const ['Unclaimed', 'Claimed', 'Packed'],
              activeFilter: _statusFilter,
              onFilterChanged: (f) => setState(() => _statusFilter = f),
            ),
          ),
          // Add item input — always shown regardless of list state
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _buildAddItemInput(),
            ),
          ),
          if (filteredItems.isEmpty && items.isNotEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'No items match your filter',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColorTokens.light.textSecondary,
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
                onAction: _focusAddField,
                accentGradient: LinearGradient(
                  colors: [
                    AppColorTokens.light.moduleGear,
                    AppColorTokens.light.moduleGearLight
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
                    color: AppColorTokens.light.textMuted,
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
                        onTogglePacked: _togglePacked,
                        onMenuAction: _handleMenuAction,
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

  Widget _buildAddItemInput() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColorTokens.light.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColorTokens.light.inputFill),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Iconsax.flash,
              color: _isHighPriority
                  ? AppColorTokens.light.errorText
                  : AppColorTokens.light.textMuted,
              size: 20,
            ),
            onPressed: () {
              HapticService.lightClick();
              setState(() => _isHighPriority = !_isHighPriority);
            },
          ),
          Expanded(
            child: TextField(
              controller: _itemController,
              inputFormatters: [LengthLimitingTextInputFormatter(100)],
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'ADD GEAR ITEM...',
                hintStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: AppColorTokens.light.textMuted,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onSubmitted: (_) => _addItem(),
            ),
          ),
          IconButton(
            icon: Icon(
              Iconsax.add_circle,
              color: AppColorTokens.light.primary,
              size: 28,
            ),
            onPressed: () {
              HapticService.lightClick();
              _addItem();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingAction() {
    return FloatingActionButton(
      onPressed: () {
        HapticService.lightClick();
        setState(() => _hideClaimed = !_hideClaimed);
      },
      backgroundColor: AppColorTokens.light.textPrimary,
      elevation: 4,
      shape: const CircleBorder(),
      tooltip: _hideClaimed ? 'Show All' : 'Hide Claimed',
      child: Icon(
        _hideClaimed ? Iconsax.eye : Iconsax.eye_slash,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return EmptyStateView(
      icon: Iconsax.warning_2,
      title: "Couldn't load Gear",
      message: 'Check your connection and try again.',
      actionLabel: 'Reload',
      onAction: () => ref.invalidate(eventGearItemsProvider(_eventRef)),
      iconColor: AppColorTokens.light.textSecondary,
    );
  }

  void _focusAddField() {
    // Scroll to add item input — handled by scroll view
  }

  Future<void> _handleMenuAction(String action, GearItem item) async {
    switch (action) {
      case 'priority':
        HapticService.selection();
        try {
          await ref.read(gearServiceProvider).updateGearItem(
                groupId: widget.groupId,
                eventId: widget.eventId,
                gearItemId: item.id,
                isHighPriority: !item.isHighPriority,
              );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text("Couldn't update priority \u2014 try again")),
            );
          }
        }
        break;
      case 'claim':
        HapticService.selection();
        final uid = ref.read(currentUserProvider)?.uid;
        if (uid == null) break;
        try {
          await ref.read(gearServiceProvider).updateGearItem(
                groupId: widget.groupId,
                eventId: widget.eventId,
                gearItemId: item.id,
                assignedTo: uid,
              );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text("Couldn't claim item \u2014 try again")),
            );
          }
        }
        break;
      case 'unclaim':
        HapticService.selection();
        try {
          await ref.read(gearServiceProvider).unclaimGearItem(
                groupId: widget.groupId,
                eventId: widget.eventId,
                gearItemId: item.id,
              );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text("Couldn't unclaim item \u2014 try again")),
            );
          }
        }
        break;
      case 'delete':
        HapticService.warning();
        _confirmDelete(item);
        break;
    }
  }

  void _confirmDelete(GearItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColorTokens.light.cardSurface,
        title: const Text(
          'DELETE ITEM',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text('Remove ${item.itemName} from the gear list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            key: GearKeys.deleteConfirmButton,
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'DELETE',
              style: TextStyle(color: AppColorTokens.light.errorText),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(gearServiceProvider).deleteGearItem(
              groupId: widget.groupId,
              eventId: widget.eventId,
              gearItemId: item.id,
            );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("Couldn't delete item \u2014 try again")),
          );
        }
      }
    }
  }

  void _addItem() async {
    final name = _itemController.text.trim();
    if (name.isEmpty) return;

    final isLoading = ref.read(gearLoadingProvider);
    if (isLoading) return;
    ref.read(gearLoadingProvider.notifier).state = true;

    _itemController.clear();
    final wasHighPriority = _isHighPriority;
    setState(() => _isHighPriority = false);

    try {
      final items =
          ref.read(eventGearItemsProvider(_eventRef)).valueOrNull ?? [];
      final nextSeqId = items.isEmpty
          ? 1
          : items.map((i) => i.sequenceId).reduce((a, b) => a > b ? a : b) + 1;

      await ref.read(gearServiceProvider).addGearItem(
            groupId: widget.groupId,
            eventId: widget.eventId,
            itemName: name,
            isHighPriority: wasHighPriority,
            sequenceId: nextSeqId,
          );
      HapticService.success();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Couldn't add item \u2014 try again")),
        );
      }
    } finally {
      ref.read(gearLoadingProvider.notifier).state = false;
    }
  }

  void _togglePacked(GearItem item, bool isMine) {
    if (!isMine && item.assignedTo != null) return;

    ref
        .read(gearServiceProvider)
        .togglePacked(
          groupId: widget.groupId,
          eventId: widget.eventId,
          gearItemId: item.id,
          isPacked: !item.isPacked,
        )
        .catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text("Couldn't update packed status \u2014 try again")),
        );
      }
    });
  }
}
