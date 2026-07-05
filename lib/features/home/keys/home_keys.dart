import 'package:flutter/material.dart';

abstract final class HomeKeys {
  // Screen key
  static const screen = Key('home_screen');

  // Header
  static const yourGroupsHeader = Key('home_your_groups_header');

  // Spacing seam: gap below the GROUPS header so the new-group CTA and the
  // first row's balance don't read as one unit in RTL (#161).
  static const groupsHeaderGap = Key('home_groups_header_gap');

  // Actions
  static const createGroupFab = Key('home_create_group_fab');
  static const profileAvatar = Key('home_profile_avatar');
  static const createGroupOption = Key('home_create_group_option');
  static const joinGroupOption = Key('home_join_group_option');

  // #818 Wave 4.1: "Set your name" chip beside the avatar — shown only while
  // deviceName is empty, tap opens the edit-name sheet directly.
  static const setNameChip = Key('home_set_name_chip');

  // #818 Wave 4.3: persistent one-line guest explainer under the greeting
  // strip — shown only while the user is anonymous, never dismissible.
  static const guestAccountCaption = Key('home_guest_account_caption');

  // Dashboard sections
  static const balanceHeroCard = Key('home_balance_hero_card');
  // Falaj rebrand PR-3: brass corner seal on the journey ticket stub.
  static const journeyTicketSeal = Key('home_journey_ticket_seal');
  // #244: shown on the hero when the cross-group balance is a partial sum
  // (a per-event money read failed for some group).
  static const balanceIncompleteNotice = Key('home_balance_incomplete_notice');
  static const activitySection = Key('home_activity_section');

  // #285: one-time, non-blocking nudge to back up an anonymous account by
  // linking an email — shown under the hero only while the user is anonymous.
  static const accountBackupNudge = Key('home_account_backup_nudge');
  static const accountBackupNudgeCta = Key('home_account_backup_nudge_cta');
  static const accountBackupNudgeDismiss = Key(
    'home_account_backup_nudge_dismiss',
  );

  // Bottom navigation
  static const bottomNavGroups = Key('home_bottom_nav_groups');
  static const bottomNavActivity = Key('home_bottom_nav_activity');
  static const bottomNavProfile = Key('home_bottom_nav_profile');
  // #808 PR2: unread dot on the Activity destination (inactive icon).
  static const activityUnreadBadge = Key('home_activity_unread_badge');

  // #818 Wave 5.2: top-bar notification bell — selects the History tab.
  static const activityBell = Key('home_activity_bell');
  // #840 PR-4: unread dot on the top-bar bell itself. NEVER reuse
  // activityUnreadBadge — HomeScreen contains BottomNavShell, so both
  // badges coexist and a shared key blows up `tester.widget<Badge>` reads.
  static const bellUnreadBadge = Key('home_bell_unread_badge');

  // #364: persistent add-expense FAB on the tab shell + its target picker
  static const addExpenseFab = Key('home_add_expense_fab');
  static const addExpenseSheet = Key('home_add_expense_sheet');
  static const addExpenseSheetBrowseAll = Key(
    'home_add_expense_sheet_browse_all',
  );
  static const addExpenseSheetBack = Key('home_add_expense_sheet_back');
  static const addExpenseSheetCreateGroup = Key(
    'home_add_expense_sheet_create_group',
  );

  // PR-5 §3: per-group balance breakdown sheet opened from the hero tap.
  static const heroBreakdownSheet = Key('home_hero_breakdown_sheet');
}
