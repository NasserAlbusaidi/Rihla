import 'package:flutter/material.dart';

abstract final class HomeKeys {
  // Screen key
  static const screen = Key('home_screen');

  // Header
  static const yourGroupsHeader = Key('home_your_groups_header');

  // Actions
  static const createGroupFab = Key('home_create_group_fab');
  static const profileAvatar = Key('home_profile_avatar');
  static const createGroupOption = Key('home_create_group_option');
  static const joinGroupOption = Key('home_join_group_option');

  // Dashboard sections
  static const balanceHeroCard = Key('home_balance_hero_card');
  static const quickActionTray = Key('home_quick_action_tray');
  static const activitySection = Key('home_activity_section');
  static const weeklySpendingCard = Key('home_weekly_spending_card');

  // Quick-action buttons
  static const addExpenseAction = Key('home_add_expense_action');
  static const settleUpAction = Key('home_settle_up_action');
  static const inviteAction = Key('home_invite_action');
  static const activityAction = Key('home_activity_action');

  // Bottom navigation
  static const bottomNavGroups = Key('home_bottom_nav_groups');
  static const bottomNavActivity = Key('home_bottom_nav_activity');
  static const bottomNavChats = Key('home_bottom_nav_chats');
  static const bottomNavProfile = Key('home_bottom_nav_profile');
}
