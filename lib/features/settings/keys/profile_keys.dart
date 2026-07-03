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
  // #488: explicit error state for the stats grid (≠ the loading skeleton).
  static const statsErrorCard = Key('profile_stats_error_card');

  // Phase 26 keys — notifications, about, and support sections
  static const notificationToggleTile = Key('profile_notification_toggle_tile');
  static const notificationSwitch = Key('profile_notification_switch');
  static const versionTile = Key('profile_version_tile');
  static const feedbackTile = Key('profile_feedback_tile');
  static const licensesTile = Key('profile_licenses_tile');
  static const coffeeTile = Key('profile_coffee_tile');

  // P3 — account recovery (linked email)
  static const linkedEmailTile = Key('profile_linked_email_tile');

  // P5 — sign out of this device (linked users only)
  static const signOutDeviceTile = Key('profile_sign_out_device_tile');

  // P6 — in-app account deletion (always visible)
  static const deleteAccountTile = Key('profile_delete_account_tile');

  // Settings cleanup pass — display section + pending recovery banner
  static const displaySection = Key('profile_display_section');
  static const pendingRecoveryBanner = Key('profile_pending_recovery_banner');

  // #487 — identity hero backup-state honesty
  static const backupStatusChip = Key('profile_backup_status_chip');
  static const backupAccountCard = Key('profile_backup_account_card');

  // #428 PR-B — account-section rework
  static const googleAccountTile = Key('profile_google_account_tile');
  static const googleLinkTile = Key('profile_google_link_tile');
  static const profileRestoreGoogleTile = Key('profile_restore_google_tile');
  static const profileRestoreEmailTile = Key('profile_restore_email_tile');

  // #487 bullet 3 — delete isolated in its own danger-zone card, separate
  // from the backup & recovery block.
  static const dangerZoneCard = Key('profile_danger_zone_card');
}
