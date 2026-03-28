import 'package:flutter/material.dart';

abstract final class HomeKeys {
  // Screen key
  static const screen = Key('home_screen');

  // Header
  static const yourGroupsHeader = Key('home_your_groups_header');

  // Actions
  static const createGroupFab = Key('home_create_group_fab');
  static const createGroupOption = Key('home_create_group_option');
  static const joinGroupOption = Key('home_join_group_option');
}
