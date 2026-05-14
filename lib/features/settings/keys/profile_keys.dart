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

  // Phase 26 keys — notifications, about, and support sections
  static const notificationToggleTile = Key('profile_notification_toggle_tile');
  static const notificationSwitch = Key('profile_notification_switch');
  static const versionTile = Key('profile_version_tile');
  static const feedbackTile = Key('profile_feedback_tile');
  static const licensesTile = Key('profile_licenses_tile');
  static const coffeeTile = Key('profile_coffee_tile');

  // T3.K — profile QR sheet
  static const qrCard = Key('profile_qr_card');

  // P3 — account recovery (linked email)
  static const linkedEmailTile = Key('profile_linked_email_tile');

  // P5 — sign out of this device (linked users only)
  static const signOutDeviceTile = Key('profile_sign_out_device_tile');
}
