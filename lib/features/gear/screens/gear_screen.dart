import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
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
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: gearAsync.when(
                data: (items) => _buildContent(items, currentUserId),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: _buildErrorState(e.toString())),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFloatingAction(),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(
              Iconsax.arrow_left,
              color: AppColors.textSecondary,
            ),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'LOADOUT / GEAR',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  widget.trip.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Iconsax.radar, color: AppColors.mint, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(List<GearItem> items, String? currentUserId) {
    if (items.isEmpty) return _buildEmptyState();

    final filteredItems = _hideClaimed
        ? items.where((i) => i.status == GearStatus.unclaimed).toList()
        : items;

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
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(
                Iconsax.bag_2,
                size: 48,
                color: AppColors.primary,
              ),
            ).animate().fadeIn().scale(delay: 100.ms),

            const SizedBox(height: 24),

            Text(
              'No Gear Yet',
              style: Theme.of(context).textTheme.headlineMedium,
            ).animate().fadeIn(delay: 200.ms),

            const SizedBox(height: 8),

            Text(
              'Add items your group needs to bring\nand claim what you\'re responsible for',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 300.ms),

            const SizedBox(height: 32),

            // Add item input
            _buildAddItemInput().animate().fadeIn(delay: 400.ms),
          ],
        ),
      ),
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
                    'TEAM READINESS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Prepare for departure',
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
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
        border: item.isHighPriority
            ? Border.all(
                color: AppColors.warning.withValues(alpha: 0.3),
                width: 1.5,
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Custom Mint Checkbox
            GestureDetector(
              onTap: () {
                HapticService.lightClick();
                _togglePacked(item, isMine);
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: item.isPacked ? AppColors.mint : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: item.isPacked ? AppColors.mint : AppColors.border,
                    width: 2,
                  ),
                  boxShadow: item.isPacked
                      ? [
                          BoxShadow(
                            color: AppColors.mint.withValues(alpha: 0.3),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildStatusChip(item.status),
                      const SizedBox(width: 8),
                      if (item.assignedTo != null) ...[
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: AppColors.surfaceLight,
                          backgroundImage: item.assignedToAvatar != null
                              ? NetworkImage(item.assignedToAvatar!)
                              : null,
                          child: item.assignedToAvatar == null
                              ? Text(
                                  item.assigneeInitials,
                                  style: const TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isMine
                              ? 'YOU'
                              : (item.assignedToName
                                        ?.split(' ')[0]
                                        .toUpperCase() ??
                                    'NONE'),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Context Menu Button
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert,
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
                  const PopupMenuItem(
                    value: 'claim',
                    child: Text('Claim Item'),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Delete Item',
                    style: TextStyle(color: AppColors.rose),
                  ),
                ),
              ],
            ),
          ],
        ),
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
            tooltip: 'High Priority',
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
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                labelText: 'Gear Item Name',
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
            tooltip: 'Add Item',
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
    return FloatingActionButton.extended(
      onPressed: () {
        HapticService.lightClick();
        setState(() => _hideClaimed = !_hideClaimed);
      },
      backgroundColor: AppColors.textPrimary,
      label: Text(
        _hideClaimed ? 'SHOW ALL' : 'HIDE CLAIMED',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
          color: Colors.white,
        ),
      ),
      icon: Icon(
        _hideClaimed ? Iconsax.eye : Iconsax.eye_slash,
        color: Colors.white,
        size: 18,
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
          'GEAR FETCH FAILED',
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
    HapticService.lightClick();
    final service = ref.read(gearServiceProvider);
    switch (action) {
      case 'priority':
        service.togglePriority(item.id, !item.isHighPriority);
        break;
      case 'claim':
        service.claimItem(item.id);
        break;
      case 'unclaim':
        service.unclaimItem(item.id);
        break;
      case 'delete':
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
        content: Text('Remove ${item.itemName.toUpperCase()} from loadout?'),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => context.pop(true),
            child: const Text(
              'DELETE',
              style: TextStyle(color: AppColors.rose),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(gearServiceProvider).deleteItem(item.id);
    }
  }

  void _addItem() async {
    final name = _itemController.text.trim();
    if (name.isEmpty) return;

    await ref
        .read(gearServiceProvider)
        .addItem(
          tripId: widget.trip.id,
          itemName: name,
          isHighPriority: _isHighPriority,
        );

    _itemController.clear();
    setState(() => _isHighPriority = false);
  }

  void _togglePacked(GearItem item, bool isMine) {
    if (!isMine && item.assignedTo != null) return;

    final service = ref.read(gearServiceProvider);

    if (item.isPacked) {
      service.unpackItem(item.id);
    } else if (item.assignedTo != null) {
      service.packItem(item.id);
    } else {
      // Claim and pack in one go
      service.claimItem(item.id).then((_) => service.packItem(item.id));
    }
  }
}
