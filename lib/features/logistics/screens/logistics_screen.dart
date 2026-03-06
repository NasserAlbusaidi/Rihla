import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../../core/theme/error_widgets.dart';
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
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subGroupsAsync = ref.watch(tripSubGroupsProvider(widget.trip.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          ModuleHeader(
            title: 'Logistics',
            subtitle: widget.trip.name.toUpperCase(),
            actions: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppColors.radiusSmall + 2),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: IconButton(
                  icon: const Icon(
                    Iconsax.add,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  onPressed: () => _showCreateDialog(),
                ),
              ),
            ],
          ),
          _buildTabBar(),
          Expanded(
            child: subGroupsAsync.when(
              data: (groups) => _buildTabContent(groups),
              loading: () => SkeletonLoader.groupList(),
              error: (e, _) => NetworkErrorWidget(
                onRetry: () =>
                    ref.invalidate(tripSubGroupsProvider(widget.trip.id)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight, width: 1.5),
      ),
      child: TabBar(
        controller: _tabController,
        onTap: (_) => setState(() {}),
        indicator: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerHeight: 0,
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
        tabs: [
          Tab(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Iconsax.car, size: 18),
                const SizedBox(width: 8),
                const Text('CARS'),
              ],
            ),
          ),
          Tab(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Iconsax.house, size: 18),
                const SizedBox(width: 8),
                const Text('LODGING'),
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
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(tripSubGroupsProvider(widget.trip.id));
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: groups.length,
              itemBuilder: (context, index) => _buildGroupCard(groups[index]),
            ),
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  Text(
                    'UNASSIGNED PERSONNEL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${unassigned.length} LEFT',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: unassigned.length,
                itemBuilder: (context, index) {
                  final p = unassigned[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
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
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _showCreateDialog(),
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
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: candidateData.isNotEmpty
                  ? AppColors.primary
                  : AppColors.borderLight,
              width: candidateData.isNotEmpty ? 2 : 1.5,
            ),
            boxShadow: candidateData.isNotEmpty
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : AppColors.cardShadow,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.borderLight,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        group.type == SubGroupType.car
                            ? Iconsax.car
                            : Iconsax.house,
                        color: AppColors.primary,
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
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: group.isFull
                                    ? AppColors.warning.withValues(alpha: 0.1)
                                    : AppColors.primary.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${group.memberCount} / ${group.capacity} SLOTS FILLED',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  color: group.isFull
                                      ? AppColors.warning
                                      : AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Iconsax.more,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                      onPressed: () => _confirmDeleteGroup(group),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: List.generate(group.capacity, (index) {
                    if (index < group.members.length) {
                      return _buildMemberSlot(group.members[index], group);
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
    return Column(
      children: [
        GestureDetector(
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: AppColors.surface,
                title: const Text(
                  'REMOVE MEMBER',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                content: Text(
                  'Remove ${member.displayName?.toUpperCase()} from ${group.name.toUpperCase()}?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('CANCEL'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      'REMOVE',
                      style: TextStyle(
                        color: AppColors.rose,
                        fontWeight: FontWeight.bold,
                      ),
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
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Center(
              child: member.avatarUrl != null
                  ? ClipOval(
                      child: Image.network(
                        member.avatarUrl!,
                        fit: BoxFit.cover,
                        width: 60,
                        height: 60,
                      ),
                    )
                  : Text(
                      member.initials,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 60,
          child: Text(
            (member.displayName?.split(' ')[0] ?? 'UNK').toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptySlot(SubGroup group) {
    return GestureDetector(
      onTap: () => _showMemberPicker(group),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.borderLight,
                width: 2,
                style: BorderStyle.solid,
              ),
            ),
            child: const Icon(
              Iconsax.add,
              color: AppColors.textMuted,
              size: 20,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'OPEN',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              color: AppColors.textMuted,
            ),
          ),
        ],
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
                      error: (e, _) =>
                          const InlineErrorWidget(message: 'Unable to load'),
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
}
