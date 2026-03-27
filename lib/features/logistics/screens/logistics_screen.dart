import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_tab_bar.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../../core/theme/error_widgets.dart';
import '../../../core/services/haptic_service.dart';
import '../../events/models/event_model.dart';
import '../../groups/models/group_model.dart';
import '../../trip/models/trip_model.dart';
import '../models/sub_group_model.dart';
import '../providers/sub_group_provider.dart';
import '../widgets/subgroup_card.dart';
import '../widgets/unassigned_pool.dart';

/// Logistics Screen - Manage cars, rooms, and teams
class LogisticsScreen extends ConsumerStatefulWidget {
  final Event event;
  final Group group;

  const LogisticsScreen({super.key, required this.event, required this.group});

  @override
  ConsumerState<LogisticsScreen> createState() => _LogisticsScreenState();
}

class _LogisticsScreenState extends ConsumerState<LogisticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _nameController = TextEditingController();
  final _capacityController = TextEditingController(text: '4');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventRef = (groupId: widget.event.groupId, eventId: widget.event.id,);
    final subGroupsAsync = ref.watch(eventSubGroupsProvider(eventRef));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          ModuleHeader(
            title: 'Logistics',
            subtitle: widget.event.name.toUpperCase(),
            actions: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(AppColors.radiusSmall + 2),
                  border: Border.all(color: AppColors.border),
                ),
                child: IconButton(
                  icon: const Icon(
                    Iconsax.add,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  onPressed: _showCreateDialog,
                ),
              ),
            ],
          ),
          AppTabBar(
            controller: _tabController,
            tabs: const ['Cars', 'Rooms'],
            activeColor: AppColors.sky,
          ),
          Expanded(
            child: subGroupsAsync.when(
              data: _buildTabContent,
              loading: SkeletonLoader.groupList,
              error: (e, _) => NetworkErrorWidget(
                onRetry: () => ref.invalidate(
                  eventSubGroupsProvider(
                    (groupId: widget.event.groupId, eventId: widget.event.id,),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(List<SubGroup> allGroups) {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildGroupList(
          allGroups.where((g) => g.type == SubGroupType.car).toList(),
          SubGroupType.car,
        ),
        _buildGroupList(
          allGroups.where((g) => g.type == SubGroupType.room).toList(),
          SubGroupType.room,
        ),
      ],
    );
  }

  Widget _buildGroupList(List<SubGroup> groups, SubGroupType type) {
    if (groups.isEmpty) return _buildEmptyState(type);

    final participants = ref.watch(
      eventLogisticsParticipantsProvider(widget.event),
    );

    final assignedUserIds = groups
        .expand((g) => g.members)
        .map((m) => m.participantId)
        .toSet();

    final unassigned = participants
        .where((p) => !assignedUserIds.contains(p.id))
        .toList();

    return Column(
      children: [
        UnassignedPool(unassigned: unassigned, type: type),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(
                eventSubGroupsProvider(
                  (groupId: widget.event.groupId, eventId: widget.event.id,),
                ),
              );
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: groups.length,
              itemBuilder: (context, index) => SubgroupCard(
                group: groups[index],
                onRenameGroup: () => _showCreateDialog(group: groups[index]),
                onDeleteGroup: _confirmDeleteGroup,
                onAddMember: _showMemberPicker,
                onRemoveMember: (member, group) =>
                    _removeMember(member: member, group: group),
                onDrop: (participant) =>
                    _dropMemberOnGroup(participant: participant, group: groups[index]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(SubGroupType type) {
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
              child: Icon(
                type == SubGroupType.car ? Iconsax.car : Iconsax.house,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No ${type.pluralName} Yet',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Add your first ${type.displayName.toLowerCase()} to start\norganizing your group',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _showCreateDialog,
              icon: const Icon(Iconsax.add, size: 18),
              label: Text('Add ${type.displayName}'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMemberPicker(SubGroup group) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final participants = ref.watch(
            eventLogisticsParticipantsProvider(widget.event),
          );
          final eventRef = (groupId: widget.event.groupId, eventId: widget.event.id,);
          final allGroupsAsync = ref.watch(eventSubGroupsProvider(eventRef));
          return Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'SELECT MEMBER',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: AppColors.textMuted,
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
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'No unassigned members',
                            style: TextStyle(color: AppColors.textMuted),
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
                              backgroundColor: AppColors.background,
                              backgroundImage:
                                  p.avatarUrl != null &&
                                      p.avatarUrl!.startsWith('http')
                                  ? NetworkImage(p.avatarUrl!)
                                  : null,
                              child:
                                  p.avatarUrl == null ||
                                      !p.avatarUrl!.startsWith('http')
                                  ? Text(
                                      p.displayName?[0] ?? 'U',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.mint,
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
                              _addMemberToGroup(group: group, participant: p);
                            },
                          );
                        },
                      ),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
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
        groupId: widget.event.groupId,
        eventId: widget.event.id,
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

  Future<void> _dropMemberOnGroup({
    required Participant participant,
    required SubGroup group,
  }) async {
    try {
      await ref.read(subGroupServiceProvider).addMember(
        groupId: widget.event.groupId,
        eventId: widget.event.id,
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

  Future<void> _addMemberToGroup({
    required SubGroup group,
    required Participant participant,
  }) async {
    try {
      await ref.read(subGroupServiceProvider).addMember(
        groupId: widget.event.groupId,
        eventId: widget.event.id,
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
        backgroundColor: AppColors.surface,
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
            onPressed: () {
              Navigator.pop(context);
              _deleteGroup(group);
            },
            child: const Text(
              'DELETE',
              style: TextStyle(color: AppColors.rose),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGroup(SubGroup group) async {
    try {
      await ref.read(subGroupServiceProvider).deleteSubGroup(
        groupId: widget.event.groupId,
        eventId: widget.event.id,
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
    final type =
        group?.type ??
        (_tabController.index == 0 ? SubGroupType.car : SubGroupType.room);

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
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              group != null ? 'EDIT GROUP' : 'NEW GROUP',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: AppColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            TextField(
              controller: _nameController,
              autofocus: true,
              inputFormatters: [LengthLimitingTextInputFormatter(50)],
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: type == SubGroupType.car
                    ? 'CAR NAME (e.g. DEFENDER 1)'
                    : 'ROOM NAME (e.g. TENT 01)',
                prefixIcon: Icon(
                  type == SubGroupType.car ? Iconsax.car : Iconsax.house,
                  color: AppColors.textMuted,
                ),
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
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                hintText: 'CAPACITY',
                prefixIcon: Icon(Iconsax.people, color: AppColors.textMuted),
              ),
            ),

            const SizedBox(height: 24),

            Consumer(
              builder: (context, ref, _) {
                final isLoading = ref.watch(subGroupLoadingProvider);
                return SizedBox(
                  height: 64,
                  child: ElevatedButton(
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
                                type: type,
                                capacity: capacity,
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.mint,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
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
        groupId: widget.event.groupId,
        eventId: widget.event.id,
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
        groupId: widget.event.groupId,
        eventId: widget.event.id,
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
