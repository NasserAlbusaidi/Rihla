/// EditExpenseScopeSection — scope tab selector + car sub-group picker for the
/// edit-expense flow.
///
/// **Why a new widget instead of reusing [SplitScopeSelector]?**
/// The edit-expense scope section has three edit-mode-specific behaviours absent
/// from the add-expense [SplitScopeSelector]:
///   1. A ChoiceChip row for car sub-groups (reads [eventSubGroupsProvider]).
///   2. A different tab selected-state visual: primary-colour fill + white text
///      (vs. the card-surface + shadow style in SplitScopeSelector).
///   3. The custom participant picker receives an empty list (participants not
///      loaded in this section; this is a known limitation of the current edit
///      flow — custom participant editing is a future enhancement).
///
/// Reusing SplitScopeSelector would have required adding edit-specific branches
/// inside the shared widget, which would violate the single-responsibility rule.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/services/haptic_service.dart';
import '../../logistics/models/sub_group_model.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../../../core/types/event_ref.dart';
import '../models/expense_model.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Scope tab (Global / My Car / Custom / Personal) plus car sub-group picker
/// for edit-expense. All mutable state lives on the parent screen; this widget
/// is purely presentational and receives callbacks.
class EditExpenseScopeSection extends ConsumerWidget {
  final String groupId;
  final String eventId;
  final ExpenseScope scope;
  final ValueChanged<ExpenseScope> onScopeChanged;
  final String? selectedSubGroupId;
  final ValueChanged<String?> onSubGroupIdChanged;
  final Set<String> customSplitParticipants;
  final ValueChanged<Set<String>> onCustomSplitChanged;

  const EditExpenseScopeSection({
    super.key,
    required this.groupId,
    required this.eventId,
    required this.scope,
    required this.onScopeChanged,
    required this.selectedSubGroupId,
    required this.onSubGroupIdChanged,
    required this.customSplitParticipants,
    required this.onCustomSplitChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final EventRef eventRef = (groupId: groupId, eventId: eventId);
    final subGroupsAsync = ref.watch(eventSubGroupsProvider(eventRef));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SPLIT TYPE',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: context.colors.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: context.colors.inputFill,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _ScopeTab(
                    label: 'Global',
                    scope: ExpenseScope.global,
                    icon: Iconsax.global,
                    isSelected: scope == ExpenseScope.global,
                    onTap: () => _handleScopeChange(ExpenseScope.global),
                  ),
                  _ScopeTab(
                    label: 'My Car',
                    scope: ExpenseScope.subGroup,
                    icon: Iconsax.car,
                    isSelected: scope == ExpenseScope.subGroup,
                    onTap: () => _handleScopeChange(ExpenseScope.subGroup),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _ScopeTab(
                    label: 'Custom',
                    scope: ExpenseScope.custom,
                    icon: Iconsax.people,
                    isSelected: scope == ExpenseScope.custom,
                    onTap: () => _handleScopeChange(ExpenseScope.custom),
                  ),
                  _ScopeTab(
                    label: 'Personal',
                    scope: ExpenseScope.personal,
                    icon: Iconsax.user,
                    isSelected: scope == ExpenseScope.personal,
                    onTap: () => _handleScopeChange(ExpenseScope.personal),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Sub-group car selector (edit-mode only — shows car ChoiceChips)
        if (scope == ExpenseScope.subGroup)
          subGroupsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (err, _) => const SizedBox.shrink(),
            data: (subGroups) {
              final cars = subGroups
                  .where((s) => s.type == SubGroupType.car)
                  .toList();
              if (cars.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 8,
                  children: cars.map((car) {
                    final isSelected = car.id == selectedSubGroupId;
                    return ChoiceChip(
                      label: Text(car.name),
                      selected: isSelected,
                      onSelected: (_) => onSubGroupIdChanged(car.id),
                    );
                  }).toList(),
                ),
              );
            },
          ),
      ],
    );
  }

  void _handleScopeChange(ExpenseScope newScope) {
    HapticService.lightClick();
    onScopeChanged(newScope);
  }
}

/// Private scope tab pill — primary fill when selected, transparent otherwise.
class _ScopeTab extends StatelessWidget {
  final String label;
  final ExpenseScope scope;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ScopeTab({
    required this.label,
    required this.scope,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? context.colors.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? Colors.white
                    : context.colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? Colors.white
                      : context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
