/// EditExpenseScopeSection — scope tab selector for the edit-expense flow.
///
/// Phase 39 strip: the "My Car" tab and sub-group ChoiceChip row are removed
/// along with the logistics feature. Surviving scopes are global, custom, personal.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/services/haptic_service.dart';
import '../models/expense_model.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Scope tab (Global / Custom / Personal) for edit-expense. All mutable state
/// lives on the parent screen; this widget is purely presentational and
/// receives callbacks.
class EditExpenseScopeSection extends ConsumerWidget {
  final String groupId;
  final String eventId;
  final ExpenseScope scope;
  final ValueChanged<ExpenseScope> onScopeChanged;
  final Set<String> customSplitParticipants;
  final ValueChanged<Set<String>> onCustomSplitChanged;

  const EditExpenseScopeSection({
    super.key,
    required this.groupId,
    required this.eventId,
    required this.scope,
    required this.onScopeChanged,
    required this.customSplitParticipants,
    required this.onCustomSplitChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          child: Row(
            children: [
              _ScopeTab(
                label: 'Global',
                scope: ExpenseScope.global,
                icon: Iconsax.global,
                isSelected: scope == ExpenseScope.global,
                onTap: () => _handleScopeChange(ExpenseScope.global),
              ),
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
