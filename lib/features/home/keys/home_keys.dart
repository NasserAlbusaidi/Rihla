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
  static const activitySection = Key('home_activity_section');

  // Bottom navigation
  static const bottomNavGroups = Key('home_bottom_nav_groups');
  static const bottomNavActivity = Key('home_bottom_nav_activity');
  static const bottomNavProfile = Key('home_bottom_nav_profile');
}
