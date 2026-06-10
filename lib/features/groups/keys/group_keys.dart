import 'package:flutter/material.dart';

abstract final class GroupKeys {
  // Screen keys (D-10: mandatory for all screens)
  static const detailScreen = Key('group_detail_screen');
  static const createScreen = Key('group_create_screen');
  static const joinScreen = Key('group_join_screen');
  static const settleUpScreen = Key('group_settle_up_screen');
  static const settingsScreen = Key('group_settings_screen');
  static const activityScreen = Key('group_activity_screen');
  static const currencyField = Key('group_create_currency_field');

  // Section keys
  static const membersAndBalancesSection =
      Key('group_members_and_balances_section');
  static const inviteCodeSection = Key('group_invite_code_section');
  static const eventsSection = Key('group_events_section');

  // Action keys
  static const createGroupButton = Key('group_create_button');
  static const joinGroupButton = Key('group_join_button');
  static const settleUpButton = Key('group_settle_up_button');
  static const groupDetailInviteButton = Key('group_detail_invite_button');
  static const recordSettlementButton = Key('group_record_settlement_button');
  static const markAsPaidButton = Key('group_mark_as_paid_button');
  static const notNowButton = Key('group_not_now_button');
  static const deleteGroupButton = Key('group_delete_button');
  static const leaveGroupButton = Key('group_leave_button');

  // Input keys
  static const groupNameInput = Key('group_name_input');
  static const joinCodeInput = Key('group_join_code_input');
  static const deviceNameInput = Key('group_device_name_input');

  // Label / empty state keys
  static const noGroupsEmpty = Key('group_no_groups_empty');
  static const noEventsEmpty = Key('group_no_events_empty');
  static const settingsTitle = Key('group_settings_title');
  static const settingsGroupNameTile = Key('group_settings_group_name_tile');
  static const settingsCurrencyTile = Key('group_settings_currency_tile');
  static const settingsInviteCodeTile = Key('group_settings_invite_code_tile');

  // Stats grid keys (Phase 20 redesign — D-08)
  static const statsGrid = Key('group_stats_grid');
  static const statYourBalance = Key('group_stat_your_balance');
  static const statGroupTotal = Key('group_stat_group_total');
  static const statActiveMembers = Key('group_stat_active_members');
  static const statEvents = Key('group_stat_events');
  static const settleUpCta = Key('group_settle_up_cta');

  // Section header keys (for GroupDetailScreen)
  static const recentActivitySection = Key('group_recent_activity_section');
  static const eventsCountChip = Key('group_events_count_chip');
  static const groupBalancesLabel = Key('group_balances_label');
  static const seeAllActivityButton = Key('group_see_all_activity_button');

  // Settle Up screen keys
  static const settleUpTitle = Key('group_settle_up_title');
  static const settleUpSummaryCard = Key('group_settle_up_summary_card');
  static const settleUpGroupTotalLabel = Key('group_settle_up_total_label');
  static const settleUpAllSettledMessage = Key('group_settle_up_all_settled');
  static const settleUpRecordSheetTitle = Key('group_settle_up_record_title');

  static const settleUpRecordPaymentButton =
      Key('group_settle_up_record_payment_button');

  // #359: share a plain-text receipt of a recorded payment.
  static const settleUpShareReceiptButton =
      Key('group_settle_up_share_receipt_button');

  // Phase 30 — Activity screen filter chip keys (added Wave 0; used by Plan 03 implementation)
  static const activityFilterAll = Key('group_activity_filter_all');
  static const activityFilterSettlements =
      Key('group_activity_filter_settlements');
  static const activityFilterEvents = Key('group_activity_filter_events');
  static const activityFilterMembers = Key('group_activity_filter_members');

  // MemberBalanceCard keys
  static const settledBadge = Key('group_member_settled_badge');
  static const settleButton = Key('group_member_settle_button');

  // ActivityScreen header keys
  static const activityScreenTitle = Key('group_activity_screen_title');
  static const activityBackButton = Key('group_activity_back_button');

  // Parameterized keys for list items
  static Key groupCard(String groupId) => Key('group_card_$groupId');
  static Key settlementTile(String id) => Key('group_settlement_tile_$id');

  // Phase 29 — Group Management

  // GroupSettingsScreen layout
  static const settingsBackButton = Key('group_settings_back_button');

  // GroupInfoSection
  static const infoSection = Key('group_info_section');
  static const groupNameEditIcon = Key('group_settings_group_name_edit_icon');
  static const inviteCodeCopyButton = Key('group_settings_invite_code_copy');
  static const inviteQrCard = Key('group_settings_invite_qr_card');
  static const inviteWhatsAppButton = Key('group_invite_whatsapp_button');

  // GroupMembersSection
  static const membersSection = Key('group_members_section');
  static const creatorBadge = Key('group_member_creator_badge');

  // GroupDangerSection
  static const dangerSection = Key('group_danger_section');
  static const leaveGroupTile = Key('group_leave_tile');
  static const deleteGroupTile = Key('group_delete_tile');
  static const leaveGroupDialog = Key('group_leave_dialog');
  static const deleteGroupDialog = Key('group_delete_dialog');
  static const leaveGroupConfirmButton = Key('group_leave_confirm_button');
  static const deleteGroupConfirmButton = Key('group_delete_confirm_button');

  // Parameterized keys for member list
  static Key memberTile(String memberId) => Key('group_member_tile_$memberId');
  static Key removeMemberButton(String memberId) =>
      Key('group_member_remove_$memberId');
}
