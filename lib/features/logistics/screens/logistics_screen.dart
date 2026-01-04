import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/haptic_service.dart';
import '../../trip/models/trip_model.dart';
import '../../trip/providers/trip_provider.dart';
import '../models/sub_group_model.dart';
import '../providers/sub_group_provider.dart';

/// Logistics Screen - Manage cars, rooms, and teams
class LogisticsScreen extends ConsumerStatefulWidget {
  final Trip trip;

  const LogisticsScreen({super.key, required this.trip});

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subGroupsAsync = ref.watch(tripSubGroupsProvider(widget.trip.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildTabBar(),
            Expanded(
              child: subGroupsAsync.when(
                data: (groups) => _buildTabContent(groups),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
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
                  'LOGISTICS / CONVOY',
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
          IconButton(
            icon: const Icon(
              Iconsax.add_circle,
              color: AppColors.mint,
              size: 28,
            ),
            onPressed: () => _showCreateDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        controller: _tabController,
        onTap: (_) => setState(() {}),
        indicator: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerHeight: 0,
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Iconsax.car, size: 16),
                const SizedBox(width: 8),
                const Text('VEHICLES'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Iconsax.house, size: 16),
                const SizedBox(width: 8),
                const Text('ROOMS'),
              ],
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

    return Column(
      children: [
        _buildUnassignedPool(groups, type),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: groups.length,
            itemBuilder: (context, index) => _buildGroupCard(groups[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildUnassignedPool(List<SubGroup> groups, SubGroupType type) {
    final participantsAsync = ref.watch(
      tripLogisticsParticipantsProvider(widget.trip.id),
    );

    return participantsAsync.when(
      data: (participants) {
        // Find participants not in any group of this type
        final assignedUserIds = groups
            .expand((g) => g.members)
            .map((m) => m.participantId)
            .toSet();

        final unassigned = participants
            .where((p) => !assignedUserIds.contains(p.id))
            .toList();

        if (unassigned.isEmpty) return const SizedBox.shrink();

        return Container(
          height: 100,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'UNASSIGNED PERSONNEL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: unassigned.length,
                  itemBuilder: (context, index) {
                    final p = unassigned[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Draggable<Participant>(
                        data: p,
                        feedback: _buildPoolItem(p, isFeedback: true),
                        childWhenDragging: Opacity(
                          opacity: 0.3,
                          child: _buildPoolItem(p),
                        ),
                        onDragStarted: () => HapticService.selection(),
                        child: _buildPoolItem(p),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(height: 100),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildPoolItem(Participant p, {bool isFeedback = false}) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: isFeedback
                ? AppColors.cardShadowLarge
                : AppColors.cardShadow,
            border: Border.all(color: AppColors.surfaceLight, width: 2),
          ),
          child: Center(
            child: p.avatarUrl != null
                ? ClipOval(
                    child: Image.network(p.avatarUrl!, fit: BoxFit.cover),
                  )
                : Text(
                    (p.displayName ?? 'U')[0].toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 60,
          child: Text(
            (p.displayName?.split(' ')[0] ?? 'UNK').toUpperCase(),
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              color: AppColors.textMuted,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
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
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(SubGroup group) {
    return DragTarget<Participant>(
      onWillAcceptWithDetails: (details) => !group.isFull,
      onAcceptWithDetails: (details) async {
        HapticService.lightClick();
        await ref
            .read(subGroupServiceProvider)
            .addMember(subGroupId: group.id, participantId: details.data.id);
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: candidateData.isNotEmpty
                  ? AppColors.mint
                  : AppColors.surfaceLight,
              width: 2,
            ),
            boxShadow: AppColors.cardShadow,
          ),
          child: Column(
            children: [
              // Tactical Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        group.type == SubGroupType.car
                            ? Iconsax.car
                            : Iconsax.house,
                        color: AppColors.textPrimary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _showCreateDialog(group: group),
                        behavior: HitTestBehavior.opaque,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.name.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${group.memberCount}/${group.capacity} SLOTS FILLED',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: group.isFull
                                    ? AppColors.warning
                                    : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Iconsax.trash,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                      onPressed: () => _confirmDeleteGroup(group),
                    ),
                  ],
                ),
              ),

              // Member Slots Grid
              Container(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(group.capacity, (index) {
                    if (index < group.members.length) {
                      final member = group.members[index];
                      return _buildMemberSlot(member, group);
                    }
                    return _buildEmptySlot(group);
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMemberSlot(SubGroupMember member, SubGroup group) {
    return GestureDetector(
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Remove Member?'),
            content: Text('Remove ${member.displayName} from ${group.name}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCEL'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'REMOVE',
                  style: TextStyle(color: AppColors.rose),
                ),
              ),
            ],
          ),
        );
        if (confirm == true) {
          HapticService.lightClick();
          await ref.read(subGroupServiceProvider).removeMember(member.id);
        }
      },
      onLongPress: () async {
        HapticService.selection();
        await ref.read(subGroupServiceProvider).removeMember(member.id);
      },
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.mint, width: 2),
            ),
            child: Center(
              child: member.avatarUrl != null
                  ? ClipOval(
                      child: Image.network(
                        member.avatarUrl!,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Text(
                      member.initials,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.mint,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 56,
            child: Text(
              (member.displayName?.split(' ')[0] ?? 'UNK').toUpperCase(),
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w900,
                color: AppColors.textMuted,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySlot(SubGroup group) {
    return GestureDetector(
      onTap: () => _showMemberPicker(group),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.background,
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.5),
            width: 2,
            style: BorderStyle.none,
          ),
        ),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.border.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: const Icon(Iconsax.add, color: AppColors.textMuted, size: 16),
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
          final participantsAsync = ref.watch(
            tripLogisticsParticipantsProvider(widget.trip.id),
          );
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
                participantsAsync.when(
                  data: (participants) {
                    final allGroupsAsync = ref.watch(
                      tripSubGroupsProvider(widget.trip.id),
                    );
                    return allGroupsAsync.when(
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
                            shrinkWrap: true,
                            itemCount: unassigned.length,
                            itemBuilder: (context, index) {
                              final p = unassigned[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: AppColors.background,
                                  backgroundImage: p.avatarUrl != null
                                      ? NetworkImage(p.avatarUrl!)
                                      : null,
                                  child: p.avatarUrl == null
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
                                onTap: () async {
                                  HapticService.lightClick();
                                  await ref
                                      .read(subGroupServiceProvider)
                                      .addMember(
                                        subGroupId: group.id,
                                        participantId: p.id,
                                      );
                                  if (context.mounted) Navigator.pop(context);
                                },
                              );
                            },
                          ),
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('Error: $e')),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _confirmDeleteGroup(SubGroup group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Logistics Unit?'),
        content: Text(
          'This will remove ${group.name} and all its assignments.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(subGroupServiceProvider).deleteSubGroup(group.id);
              if (context.mounted) Navigator.pop(context);
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
              group != null ? 'EDIT LOGISTICS UNIT' : 'NEW LOGISTICS UNIT',
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
                        : () async {
                            final name = _nameController.text.trim();
                            final capacity =
                                int.tryParse(_capacityController.text) ?? 4;

                            if (name.isEmpty) return;

                            HapticService.lightClick();

                            if (group != null) {
                              final success = await ref
                                  .read(subGroupServiceProvider)
                                  .updateSubGroup(
                                    group.id,
                                    name: name,
                                    capacity: capacity,
                                  );
                              if (success && context.mounted) {
                                Navigator.pop(context);
                              }
                            } else {
                              final result = await ref
                                  .read(subGroupServiceProvider)
                                  .createSubGroup(
                                    tripId: widget.trip.id,
                                    name: name,
                                    type: type,
                                    capacity: capacity,
                                  );

                              if (result != null && context.mounted) {
                                Navigator.pop(context);
                              }
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
                            group != null ? 'UPDATE UNIT' : 'INITIALIZE UNIT',
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
}
