import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../shared/widgets/directional_icon.dart';
import '../../groups/models/group_model.dart';
import '../../groups/providers/group_provider.dart';
import '../keys/home_keys.dart';
import '../providers/active_journeys_provider.dart';
import 'add_expense_fab.dart';

enum _SheetView { flattened, groups, groupEvents }

/// Flattened group→event target picker for the add-expense FAB (#364).
///
/// Opens on the window-active open events across all groups (ongoing first);
/// the browse-all footer falls back to a two-step group → event flow for the
/// long tail. Every tap ends in a path-based push of the existing add route.
class AddExpenseTargetSheet extends ConsumerStatefulWidget {
  const AddExpenseTargetSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const AddExpenseTargetSheet(),
    );
  }

  @override
  ConsumerState<AddExpenseTargetSheet> createState() =>
      _AddExpenseTargetSheetState();
}

class _AddExpenseTargetSheetState extends ConsumerState<AddExpenseTargetSheet> {
  // Resolved once on first data so a stream refresh never yanks the user out
  // of the page they are on.
  _SheetView? _view;
  String? _groupId;
  String? _groupName;

  void _pushTarget(AddExpenseTarget target) {
    HapticService.lightClick();
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(addExpensePathFor(target));
  }

  void _pushCreateGroup() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push('/create-group');
  }

  String _subtitleFor(AddExpenseTarget target, DateTime now) {
    final l10n = context.l10n;
    final start = target.startDate;
    final end = target.endDate;
    if (start != null &&
        end != null &&
        now.isAfter(start.subtract(const Duration(seconds: 1))) &&
        now.isBefore(end.add(const Duration(days: 1)))) {
      return l10n.addExpenseSheetSubtitleOngoing(target.groupName);
    }
    if (start != null && start.isAfter(now)) {
      final days = (start.difference(now).inHours / 24).ceil().clamp(1, 365);
      return l10n.addExpenseSheetSubtitleUpcoming(target.groupName, days);
    }
    return target.groupName;
  }

  @override
  Widget build(BuildContext context) {
    final targetsAsync = ref.watch(addExpenseTargetsProvider);
    final groupsAsync = ref.watch(userGroupsProvider);
    final targets = targetsAsync.valueOrNull;
    final groups = groupsAsync.valueOrNull;

    Widget body;
    if (targetsAsync.hasError || groupsAsync.hasError) {
      body = _Message(text: context.l10n.addExpenseSheetLoadFailed);
    } else if (targets == null || groups == null) {
      body = const _Loading();
    } else if (groups.isEmpty) {
      body = _EmptyBody(onCreateGroup: _pushCreateGroup);
    } else {
      _view ??= targets.active.isNotEmpty
          ? _SheetView.flattened
          : _SheetView.groups;
      body = switch (_view!) {
        _SheetView.flattened => _buildFlattened(targets),
        _SheetView.groups => _buildGroups(targets, groups),
        _SheetView.groupEvents => _buildGroupEvents(targets),
      };
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Padding(
          key: HomeKeys.addExpenseSheet,
          padding: EdgeInsetsDirectional.only(
            start: context.spacing.space24,
            end: context.spacing.space24,
            top: context.spacing.space16,
            bottom: context.spacing.space16,
          ),
          child: body,
        ),
      ),
    );
  }

  Widget _header({required String title, String? subtitle, bool back = false}) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (back)
          IconButton(
            key: HomeKeys.addExpenseSheetBack,
            onPressed: () => setState(() {
              _view = _view == _SheetView.groupEvents
                  ? _SheetView.groups
                  : _SheetView.flattened;
            }),
            icon: DirectionalIcon(
              Iconsax.arrow_left,
              size: 20,
              color: colors.textPrimary,
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              if (subtitle != null) ...[
                SizedBox(height: context.spacing.space4),
                Text(
                  subtitle,
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _targetTile(AddExpenseTarget target, DateTime now) {
    final colors = context.colors;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(target.eventName),
      subtitle: Text(
        _subtitleFor(target, now),
        style: TextStyle(color: colors.textSecondary, fontSize: 12),
      ),
      trailing: DirectionalIcon(
        Iconsax.arrow_right_3,
        size: 16,
        color: colors.textSecondary,
      ),
      onTap: () => _pushTarget(target),
    );
  }

  Widget _buildFlattened(AddExpenseTargets targets) {
    final l10n = context.l10n;
    final now = DateTime.now();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(
          title: l10n.addExpenseSheetTitle,
          subtitle: l10n.addExpenseSheetSubtitle,
        ),
        SizedBox(height: context.spacing.space8),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final target in targets.active) _targetTile(target, now),
            ],
          ),
        ),
        ListTile(
          key: HomeKeys.addExpenseSheetBrowseAll,
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.addExpenseSheetBrowseAll,
            style: TextStyle(color: context.colors.primary),
          ),
          trailing: DirectionalIcon(
            Iconsax.arrow_right_3,
            size: 16,
            color: context.colors.primary,
          ),
          onTap: () => setState(() => _view = _SheetView.groups),
        ),
      ],
    );
  }

  Widget _buildGroups(AddExpenseTargets targets, List<Group> groups) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(
          title: l10n.addExpenseSheetAllGroupsTitle,
          subtitle: l10n.addExpenseSheetAllGroupsSubtitle,
          back: targets.active.isNotEmpty,
        ),
        SizedBox(height: context.spacing.space8),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final group in groups)
                _groupTile(
                  targets,
                  groupId: group.id,
                  groupName: group.name,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _groupTile(
    AddExpenseTargets targets, {
    required String groupId,
    required String groupName,
  }) {
    final colors = context.colors;
    final open = targets.openByGroup[groupId] ?? const [];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: open.isNotEmpty,
      title: Text(groupName),
      subtitle: Text(
        context.l10n.addExpenseSheetOpenEventCount(open.length),
        style: TextStyle(color: colors.textSecondary, fontSize: 12),
      ),
      trailing: open.isEmpty
          ? null
          : DirectionalIcon(
              Iconsax.arrow_right_3,
              size: 16,
              color: colors.textSecondary,
            ),
      onTap: open.isEmpty
          ? null
          : () {
              // A group with exactly one open event skips its event page.
              if (open.length == 1) {
                _pushTarget(open.single);
                return;
              }
              setState(() {
                _view = _SheetView.groupEvents;
                _groupId = groupId;
                _groupName = groupName;
              });
            },
    );
  }

  Widget _buildGroupEvents(AddExpenseTargets targets) {
    final now = DateTime.now();
    final open = targets.openByGroup[_groupId] ?? const <AddExpenseTarget>[];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(
          title: _groupName ?? '',
          subtitle: context.l10n.addExpenseSheetPickEventSubtitle,
          back: true,
        ),
        SizedBox(height: context.spacing.space8),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [for (final target in open) _targetTile(target, now)],
          ),
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.space24),
      child: Text(
        text,
        style: TextStyle(color: context.colors.textSecondary),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.onCreateGroup});

  final VoidCallback onCreateGroup;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.addExpenseSheetEmptyTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        SizedBox(height: context.spacing.space4),
        Text(
          l10n.addExpenseSheetEmptyBody,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
        ),
        SizedBox(height: context.spacing.space16),
        SizedBox(
          width: double.infinity,
          height: context.spacing.buttonHeight,
          child: ElevatedButton.icon(
            key: HomeKeys.addExpenseSheetCreateGroup,
            onPressed: onCreateGroup,
            icon: const Icon(Iconsax.add),
            label: Text(l10n.homeCreateGroup),
          ),
        ),
      ],
    );
  }
}
