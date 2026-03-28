import 'package:flutter/material.dart';

abstract final class GroupKeys {
  // Screen keys (D-10: mandatory for all screens)
  static const detailScreen = Key('group_detail_screen');
  static const createScreen = Key('group_create_screen');
  static const joinScreen = Key('group_join_screen');
  static const settleUpScreen = Key('group_settle_up_screen');
  static const settingsScreen = Key('group_settings_screen');
  static const activityScreen = Key('group_activity_screen');

  // Section keys
  static const membersAndBalancesSection =
      Key('group_members_and_balances_section');
  static const inviteCodeSection = Key('group_invite_code_section');
  static const eventsSection = Key('group_events_section');

  // Action keys
  static const createGroupButton = Key('group_create_button');
  static const joinGroupButton = Key('group_join_button');
  static const settleUpButton = Key('group_settle_up_button');
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

  // Parameterized keys for list items
  static Key groupCard(String groupId) => Key('group_card_$groupId');
  static Key memberBalanceCard(String memberId) =>
      Key('group_member_balance_card_$memberId');
  static Key settlementTile(String id) => Key('group_settlement_tile_$id');
}
