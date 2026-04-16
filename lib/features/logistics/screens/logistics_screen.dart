import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/error_widgets.dart';
import '../../../shared/animations/fade_in_list.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../trip/models/trip_model.dart';
import '../keys/logistics_keys.dart';
import '../models/sub_group_model.dart';
import '../providers/sub_group_provider.dart';
import '../widgets/logistics_hero_card.dart';
import '../widgets/sub_group_card.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../shared/widgets/offline_banner.dart';

/// Logistics Screen — unified module template (D-08, D-23).
///
/// Tab bar removed (D-23). Layout: dark ModuleHeader → LogisticsHeroCard →
/// section overline → FadeInList of SubGroupCard.
/// Loading: SkeletonLoader. Empty: EmptyStateView with dusty-teal gradient.
class LogisticsScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String eventId;

  const LogisticsScreen({
    super.key,
    required this.groupId,
    required this.eventId,
  });

  @override
  ConsumerState<LogisticsScreen> createState() => _LogisticsScreenState();
}

class _LogisticsScreenState extends ConsumerState<LogisticsScreen> {
  final _nameController = TextEditingController();
  final _capacityController = TextEditingController(text: '4');

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
    final eventAsync = ref.watch(eventDetailProvider(eventRef));
    final subGroupsAsync = ref.watch(eventSubGroupsProvider(eventRef));

    // Loading state — use skeleton instead of spinner
    if (eventAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppColorTokens.light.scaffoldBackground,
        body: Column(
          children: [
            const ModuleHeader(title: 'Logistics', useDarkTheme: true),
            Expanded(child: SkeletonLoader.groupList()),
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
      key: LogisticsKeys.screen,
      backgroundColor: AppColorTokens.light.scaffoldBackground,
      body: Column(
        children: [
          ModuleHeader(
            title: 'Logistics',
            subtitle: event.name.toUpperCase(),
            useDarkTheme: true,
            actions: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8 + 2),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: IconButton(
                  icon: const Icon(
                    Iconsax.add,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: _showCreateDialog,
                ),
              ),
            ],
          ),
          const OfflineBanner(),
          Expanded(
            child: subGroupsAsync.when(
              data: (subGroups) =>
                  _buildContent(event, subGroups),
              loading: SkeletonLoader.groupList,
              error: (e, _) => NetworkErrorWidget(
                onRetry: () => ref.invalidate(
                  eventSubGroupsProvider(
                    (groupId: widget.groupId, eventId: widget.eventId),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Event event, List<SubGroup> subGroups) {
    final memberCount = subGroups
        .expand((g) => g.members)
        .map((m) => m.participantId)
        .toSet()
        .length;

    final participants = ref.watch(eventLogisticsParticipantsProvider(event));
    final assignedIds = subGroups
        .expand((g) => g.members)
        .map((m) => m.participantId)
        .toSet();
    final unassignedCount =
        participants.where((p) => !assignedIds.contains(p.id)).length;

    return CustomScrollView(
      slivers: [
        // Hero card with stats
        SliverToBoxAdapter(
          child: LogisticsHeroCard(
            groupCount: subGroups.length,
            memberCount: memberCount,
            unassignedCount: unassignedCount,
            onCreateTapped: _showCreateDialog,
          ),
        ),

        if (subGroups.isEmpty)
          SliverFillRemaining(
            child: EmptyStateView(
              icon: Iconsax.people,
              title: 'No sub-groups yet',
              message:
                  'Create sub-groups to organize transport, accommodation, or activities.',
              actionLabel: 'Create Sub-group',
              onAction: _showCreateDialog,
              accentGradient: LinearGradient(
                colors: [AppColorTokens.light.moduleLogistics, AppColorTokens.light.moduleLogisticsLight],
              ),
            ),
          )
        else ...[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              4,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                'SUB-GROUPS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppColorTokens.light.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FadeInList(
              children: subGroups.map((subGroup) {
                return SubGroupCard(
                  subGroup: subGroup,
                  onDeleteGroup: _confirmDeleteGroup,
                  onAddMember: _showMemberPicker,
                  onRemoveMember: (member, group) =>
                      _removeMember(member: member, group: group),
                );
              }).toList(),
            ),
          ),
        ],

        const SliverPadding(
          padding: EdgeInsets.only(bottom: 32),
          sliver: SliverToBoxAdapter(child: SizedBox()),
        ),
      ],
    );
  }

  void _showMemberPicker(SubGroup group) {
    final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
    final event = ref.read(eventDetailProvider(eventRef)).valueOrNull;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final participants = event != null
              ? ref.watch(eventLogisticsParticipantsProvider(event))
              : <Participant>[];
          final localEventRef = eventRef;
          final allGroupsAsync = ref.watch(eventSubGroupsProvider(localEventRef));
          return Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            decoration: BoxDecoration(
              color: AppColorTokens.light.cardSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SELECT MEMBER',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: AppColorTokens.light.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                allGroupsAsync.when(
                  data: (groups) {
                    final assignedUserIds = groups
                        .expand((g) => g.members)
                        .map((m) => m.participantId)
                        .toSet();

                    final unassigned = participants
                        .where((p) => !assignedUserIds.contains(p.id))
                        .toList();

                    if (unassigned.isEmpty) {
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'No unassigned members',
                            style: TextStyle(color: AppColorTokens.light.textMuted),
                          ),
                        ),
                      );
                    }

                    return Flexible(
                      child: ListView.builder(
                        itemCount: unassigned.length,
                        itemBuilder: (context, index) {
                          final p = unassigned[index];
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColorTokens.light.scaffoldBackground,
                              backgroundImage:
                                  p.avatarUrl != null &&
                                      p.avatarUrl!.startsWith('http')
                                  ? NetworkImage(p.avatarUrl!)
                                  : null,
                              child: p.avatarUrl == null ||
                                      !p.avatarUrl!.startsWith('http')
                                  ? Text(
                                      p.displayName?[0] ?? 'U',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppColorTokens.light.moduleLedger,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Text(
                              p.displayName ?? 'Unknown',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onTap: () {
                              HapticService.lightClick();
                              Navigator.pop(context);
                              _addMemberToGroup(
                                group: group,
                                participant: p,
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
                  loading: () => Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Loading...',
                        style: TextStyle(color: AppColorTokens.light.textMuted),
                      ),
                    ),
                  ),
                  error: (e, _) =>
                      const InlineErrorWidget(message: 'Unable to load'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _removeMember({
    required SubGroupMember member,
    required SubGroup group,
  }) async {
    try {
      await ref.read(subGroupServiceProvider).removeMember(
        groupId: widget.groupId,
        eventId: widget.eventId,
        subGroupId: group.id,
        memberId: member.id,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't remove member \u2014 try again"),
          ),
        );
      }
    }
  }

  Future<void> _addMemberToGroup({
    required SubGroup group,
    required Participant participant,
  }) async {
    try {
      await ref.read(subGroupServiceProvider).addMember(
        groupId: widget.groupId,
        eventId: widget.eventId,
        subGroupId: group.id,
        participantId: participant.id,
        displayName: participant.displayName ?? '',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't add member \u2014 try again"),
          ),
        );
      }
    }
  }

  void _confirmDeleteGroup(SubGroup group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColorTokens.light.cardSurface,
        title: const Text('Delete Group?'),
        content: Text(
          'This will remove ${group.name} and all its assignments.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            key: LogisticsKeys.deleteButton,
            onPressed: () {
              Navigator.pop(context);
              _deleteGroup(group);
            },
            child: Text(
              'DELETE',
              style: TextStyle(color: AppColorTokens.light.errorText),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGroup(SubGroup group) async {
    try {
      await ref.read(subGroupServiceProvider).deleteSubGroup(
        groupId: widget.groupId,
        eventId: widget.eventId,
        subGroupId: group.id,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't delete group \u2014 try again"),
          ),
        );
      }
    }
  }

  void _showCreateDialog({SubGroup? group}) {
    if (group != null) {
      _nameController.text = group.name;
      _capacityController.text = group.capacity.toString();
    } else {
      _nameController.clear();
      _capacityController.text = '4';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: AppColorTokens.light.cardSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              group != null ? 'EDIT GROUP' : 'NEW GROUP',
              key: group != null ? null : LogisticsKeys.createGroupTitle,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: AppColorTokens.light.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              autofocus: true,
              inputFormatters: [LengthLimitingTextInputFormatter(50)],
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColorTokens.light.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'CAR NAME (e.g. DEFENDER 1)',
                prefixIcon: Icon(Iconsax.car, color: AppColorTokens.light.textMuted),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _capacityController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                LengthLimitingTextInputFormatter(2),
                FilteringTextInputFormatter.digitsOnly,
              ],
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColorTokens.light.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'CAPACITY',
                prefixIcon:
                    Icon(Iconsax.people, color: AppColorTokens.light.textMuted),
              ),
            ),
            const SizedBox(height: 24),
            Consumer(
              builder: (context, ref, _) {
                final isLoading = ref.watch(subGroupLoadingProvider);
                return SizedBox(
                  height: 64,
                  child: ElevatedButton(
                    key:
                        group != null ? null : LogisticsKeys.createGroupButton,
                    onPressed: isLoading
                        ? null
                        : () {
                            final name = _nameController.text.trim();
                            final capacity =
                                int.tryParse(_capacityController.text) ?? 4;

                            if (name.isEmpty) return;

                            HapticService.lightClick();
                            Navigator.pop(context);

                            if (group != null) {
                              _updateGroup(
                                group: group,
                                name: name,
                                capacity: capacity,
                              );
                            } else {
                              _createGroup(
                                name: name,
                                type: SubGroupType.car,
                                capacity: capacity,
                              );
                            }
                          },
                    child: isLoading
                        ? const Text(
                            'SAVING...',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          )
                        : Text(
                            group != null ? 'SAVE CHANGES' : 'CREATE GROUP',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateGroup({
    required SubGroup group,
    required String name,
    required int capacity,
  }) async {
    try {
      await ref.read(subGroupServiceProvider).updateSubGroup(
        groupId: widget.groupId,
        eventId: widget.eventId,
        subGroupId: group.id,
        name: name,
        capacity: capacity,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't rename group \u2014 try again"),
          ),
        );
      }
    }
  }

  Future<void> _createGroup({
    required String name,
    required SubGroupType type,
    required int capacity,
  }) async {
    try {
      await ref.read(subGroupServiceProvider).createSubGroup(
        groupId: widget.groupId,
        eventId: widget.eventId,
        name: name,
        type: type.value,
        capacity: capacity,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't create group \u2014 try again"),
          ),
        );
      }
    }
  }
}
