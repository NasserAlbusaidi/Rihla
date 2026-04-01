import 'package:flutter/material.dart';

abstract final class ProfileKeys {
  static const screen = Key('profile_screen');
  static const initialsCircle = Key('profile_initials_circle');
  static const displayName = Key('profile_display_name');
  static const setNamePrompt = Key('profile_set_name_prompt');
  static const editNameSheet = Key('profile_edit_name_sheet');
  static const saveNameButton = Key('profile_save_name_button');
  static const nameTextField = Key('profile_name_text_field');
  static const statsSection = Key('profile_stats_section');
  static const statGroups = Key('profile_stat_groups');
  static const statEvents = Key('profile_stat_events');
  static const statSpent = Key('profile_stat_spent');
}
