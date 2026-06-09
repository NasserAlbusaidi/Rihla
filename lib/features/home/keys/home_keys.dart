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

  // Dashboard sections
  static const balanceHeroCard = Key('home_balance_hero_card');
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
}
