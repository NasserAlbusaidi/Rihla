import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/animations/tap_bounce.dart';
import '../keys/home_keys.dart';

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
      padding: const EdgeInsets.symmetric(
        horizontal: AppColors.space16,
        vertical: AppColors.space8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, size: 24, color: AppColors.primary),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
