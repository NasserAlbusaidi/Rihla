import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/types/event_ref.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../auth/providers/auth_provider.dart';
import '../../events/providers/event_provider.dart';
import '../keys/gear_keys.dart';
import '../models/gear_item_model.dart';
import '../providers/gear_provider.dart';
import '../widgets/gear_list_view.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../shared/widgets/offline_banner.dart';

/// Gear Screen — orchestrator (D-08).
///
/// Owns state + mutation handlers. Layout delegated to GearListView.
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
        backgroundColor: context.colors.scaffoldBackground,
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
        backgroundColor: context.colors.scaffoldBackground,
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
                iconColor: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      key: GearKeys.screen,
      backgroundColor: context.colors.scaffoldBackground,
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
              data: (items) => GearListView(
                items: items,
                currentUserId: currentUserId,
                searchQuery: _searchQuery,
                statusFilter: _statusFilter,
                hideClaimed: _hideClaimed,
                onTogglePacked: _togglePacked,
                onMenuAction: _handleMenuAction,
                onSearchChanged: (q) => setState(() => _searchQuery = q),
                onStatusFilterChanged: (f) =>
                    setState(() => _statusFilter = f),
                onRefresh: () => ref.invalidate(eventGearItemsProvider(_eventRef)),
                onAddItem: _focusAddField,
                addController: _itemController,
                isHighPriority: _isHighPriority,
                onPriorityChanged: (v) => setState(() => _isHighPriority = v),
                onSubmitAdd: _addItem,
              ),
              loading: SkeletonLoader.gearList,
              error: (e, st) => _buildErrorState(e.toString()),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingAction(),
    );
  }

  Widget _buildFloatingAction() {
    return FloatingActionButton(
      onPressed: () {
        HapticService.lightClick();
        setState(() => _hideClaimed = !_hideClaimed);
      },
      backgroundColor: context.colors.textPrimary,
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
      iconColor: context.colors.textSecondary,
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
        backgroundColor: context.colors.cardSurface,
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
              style: TextStyle(color: context.colors.errorText),
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
