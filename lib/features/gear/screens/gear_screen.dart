import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/offline_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/search_filter_bar.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../../core/services/haptic_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../trip/models/trip_model.dart';
import '../models/gear_item_model.dart';
import '../providers/gear_provider.dart';

/// Gear Screen - Packing checklist with claim functionality
class GearScreen extends ConsumerStatefulWidget {
  final Trip trip;

  const GearScreen({super.key, required this.trip});

  @override
  ConsumerState<GearScreen> createState() => _GearScreenState();
}

class _GearScreenState extends ConsumerState<GearScreen> {
  final _itemController = TextEditingController();
  bool _hideClaimed = false;
  bool _isHighPriority = false;
  String _searchQuery = '';
  String? _statusFilter;

  @override
  void dispose() {
    _itemController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gearAsync = ref.watch(tripGearProvider(widget.trip.id));
    final currentUserId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          ModuleHeader(
            title: 'Gear',
            subtitle: widget.trip.name.toUpperCase(),
          ),
          SearchFilterBar(
            onSearchChanged: (q) => setState(() => _searchQuery = q),
            hintText: 'Search gear...',
            filters: const ['Unclaimed', 'Claimed', 'Packed'],
            activeFilter: _statusFilter,
            onFilterChanged: (f) => setState(() => _statusFilter = f),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: gearAsync.when(
              data: (items) => _buildContent(items, currentUserId),
              loading: () => SkeletonLoader.cardList(),
              error: (e, _) => Center(child: _buildErrorState(e.toString())),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingAction(),
    );
  }

  Widget _buildContent(List<GearItem> items, String? currentUserId) {
    if (items.isEmpty) return _buildEmptyState();

    var filteredItems = items.where((item) {
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

    final stats = GearStats(
      total: items.length,
      unclaimed: items.where((i) => i.status == GearStatus.unclaimed).length,
      claimed: items.where((i) => i.status == GearStatus.claimed).length,
      packed: items.where((i) => i.status == GearStatus.packed).length,
    );

    return Column(
      children: [
        _buildProgressCard(stats),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(tripGearProvider(widget.trip.id));
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              itemCount: filteredItems.length + 1, // +1 for AddItemInput
              itemBuilder: (context, index) {
                if (index == 0) return _buildAddItemInput();
                return _buildGearItemCard(
                  filteredItems[index - 1],
                  currentUserId,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Text(
                'ADD YOUR FIRST ITEM',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ).animate().fadeIn(delay: 350.ms),
              const SizedBox(height: 16),
              _buildAddItemInput().animate().fadeIn(delay: 400.ms),
            ],
          ),
        ),
        const Expanded(
          child: EmptyStateView(
            icon: Iconsax.bag_2,
            title: 'No gear yet',
            message: 'Add items your group needs to bring',
            iconColor: AppColors.amber,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressCard(GearStats stats) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.cardShadowLarge,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PACKING PROGRESS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Getting ready',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.mint.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${(stats.readyPercentage * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppColors.mint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: stats.readyPercentage,
              backgroundColor: AppColors.surfaceLight,
              valueColor: const AlwaysStoppedAnimation(AppColors.mint),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Iconsax.box, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                '${stats.packed} / ${stats.total} items packed',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                '${stats.unclaimed} unclaimed',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGearItemCard(GearItem item, String? currentUserId) {
    final isMine = item.assignedTo == currentUserId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: item.isHighPriority
              ? AppColors.warning.withValues(alpha: 0.3)
              : AppColors.borderLight,
          width: item.isHighPriority ? 2 : 1.5,
        ),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticService.selection();
              _togglePacked(item, isMine);
            },
            child: AnimatedContainer(
              duration: 200.ms,
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: item.isPacked ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: item.isPacked ? AppColors.primary : AppColors.border,
                  width: 2,
                ),
                boxShadow: item.isPacked
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: item.isPacked
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.itemName.toUpperCase(),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          color: item.isPacked
                              ? AppColors.textMuted
                              : AppColors.textPrimary,
                          decoration: item.isPacked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    if (item.isHighPriority) _buildPriorityBadge(true),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildStatusChip(item.status),
                    if (item.assignedTo != null) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 8,
                              backgroundColor: AppColors.textMuted,
                              child: Text(
                                item.assigneeInitials,
                                style: const TextStyle(
                                  fontSize: 6,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isMine
                                  ? 'YOU'
                                  : (item.assignedToName
                                            ?.split(' ')[0]
                                            .toUpperCase() ??
                                        'NONE'),
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Iconsax.more,
              color: AppColors.textMuted,
              size: 20,
            ),
            onSelected: (value) => _handleMenuAction(value, item),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'priority',
                child: Text('Toggle Priority'),
              ),
              if (item.assignedTo != null)
                const PopupMenuItem(
                  value: 'unclaim',
                  child: Text('Unclaim Item'),
                ),
              if (item.assignedTo == null)
                const PopupMenuItem(value: 'claim', child: Text('Claim Item')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: AppColors.rose)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(GearStatus status) {
    final color = switch (status) {
      GearStatus.unclaimed => AppColors.textMuted,
      GearStatus.claimed => AppColors.warning,
      GearStatus.packed => AppColors.mint,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        status.displayName.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(bool isHigh) {
    if (!isHigh) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.rose.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Iconsax.flash, color: AppColors.rose, size: 10),
          SizedBox(width: 4),
          Text(
            'HIGH',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              color: AppColors.rose,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddItemInput() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Iconsax.flash,
              color: _isHighPriority ? AppColors.rose : AppColors.textMuted,
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
              decoration: const InputDecoration(
                hintText: 'ADD GEAR ITEM...',
                hintStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: AppColors.textMuted,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
              ),
              onSubmitted: (_) => _addItem(),
            ),
          ),
          IconButton(
            icon: const Icon(
              Iconsax.add_circle,
              color: AppColors.mint,
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
      backgroundColor: AppColors.textPrimary,
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Iconsax.warning_2, color: AppColors.rose, size: 48),
        const SizedBox(height: 16),
        Text(
          'Could not load gear',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: AppColors.rose,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          error,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }

  void _handleMenuAction(String action, GearItem item) {
    final repo = ref.read(offlineRepositoryProvider);
    final tripId = widget.trip.id;
    final currentUserId = ref.read(currentUserProvider)?.id;
    switch (action) {
      case 'priority':
        HapticService.selection();
        repo.updateGearItem(
          item.id,
          tripId,
          {'is_high_priority': item.isHighPriority ? 0 : 1},
        );
        break;
      case 'claim':
        HapticService.selection();
        if (currentUserId != null) {
          repo.updateGearItem(item.id, tripId, {'assigned_to': currentUserId});
        }
        break;
      case 'unclaim':
        HapticService.selection();
        repo.updateGearItem(
          item.id,
          tripId,
          {'assigned_to': null, 'is_packed': 0},
        );
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
        backgroundColor: AppColors.surface,
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
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'DELETE',
              style: TextStyle(color: AppColors.rose),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref
          .read(offlineRepositoryProvider)
          .deleteGearItem(item.id, widget.trip.id);
    }
  }

  void _addItem() async {
    final name = _itemController.text.trim();
    if (name.isEmpty) return;

    final repo = ref.read(offlineRepositoryProvider);
    final newItem = GearItem(
      id: repo.generateId(),
      tripId: widget.trip.id,
      itemName: name,
      isHighPriority: _isHighPriority,
      createdAt: DateTime.now(),
    );
    await repo.saveGearItem(newItem);

    _itemController.clear();
    setState(() => _isHighPriority = false);
  }

  void _togglePacked(GearItem item, bool isMine) {
    if (!isMine && item.assignedTo != null) return;

    final repo = ref.read(offlineRepositoryProvider);
    final currentUserId = ref.read(currentUserProvider)?.id;
    final tripId = widget.trip.id;

    if (item.isPacked) {
      repo.updateGearItem(item.id, tripId, {'is_packed': 0});
    } else if (item.assignedTo != null) {
      repo.updateGearItem(item.id, tripId, {'is_packed': 1});
    } else {
      // Claim and pack in one go
      () async {
        try {
          if (currentUserId != null) {
            await repo.updateGearItem(
              item.id,
              tripId,
              {'assigned_to': currentUserId},
            );
          }
          await repo.updateGearItem(item.id, tripId, {'is_packed': 1});
        } catch (e) {
          debugPrint('Failed to claim and pack: $e');
        }
      }();
    }
  }
}
