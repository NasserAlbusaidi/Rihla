import 'package:flutter/material.dart';

abstract final class LogisticsKeys {
  // Screen key
  static const screen = Key('logistics_screen');

  // Actions
  static const createGroupButton = Key('logistics_create_group_button');
  static const removeButton = Key('logistics_remove_button');
  static const deleteButton = Key('logistics_delete_button');
  static const createGroupTitle = Key('logistics_create_group_title');

  // Sections
  static const unassignedPool = Key('logistics_unassigned_pool');

  // Parameterized keys for list items
  static Key subgroupCard(String id) => Key('logistics_subgroup_card_$id');
}
