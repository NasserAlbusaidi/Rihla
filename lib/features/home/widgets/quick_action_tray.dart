import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../shared/animations/tap_bounce.dart';
import '../keys/home_keys.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Quick action tray for the home dashboard.
///
/// Renders 4 icon buttons in a horizontal row:
/// Add Expense, Settle Up, Invite Friend, Activity.
///
/// Each button is a [TapBounce]-wrapped Column with a 48x48 icon container
/// and a label below. Meets WCAG 48dp minimum touch target.
class QuickActionTray extends StatelessWidget {
  final VoidCallback onAddExpense;
  final VoidCallback onSettleUp;
  final VoidCallback onInviteFriend;
  final VoidCallback onActivity;

  const QuickActionTray({
    super.key,
    required this.onAddExpense,
    required this.onSettleUp,
    required this.onInviteFriend,
    required this.onActivity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: HomeKeys.quickActionTray,
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.space16,
        vertical: context.spacing.space16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _QuickActionButton(
            key: HomeKeys.addExpenseAction,
            icon: Iconsax.receipt_add,
            label: 'Add Expense',
            onTap: onAddExpense,
          ),
          _QuickActionButton(
            key: HomeKeys.settleUpAction,
            icon: Iconsax.money_recive,
            label: 'Settle Up',
            onTap: onSettleUp,
          ),
          _QuickActionButton(
            key: HomeKeys.inviteAction,
            icon: Iconsax.user_add,
            label: 'Invite Friend',
            onTap: onInviteFriend,
          ),
          _QuickActionButton(
            key: HomeKeys.activityAction,
            icon: Iconsax.activity,
            label: 'Activity',
            onTap: onActivity,
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TapBounce(
      onTap: onTap,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: context.colors.inputFillWarm,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: context.colors.border.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
              child: Icon(icon, size: 24, color: context.colors.primary),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
