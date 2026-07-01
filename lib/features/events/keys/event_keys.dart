import 'package:flutter/material.dart';

abstract final class EventKeys {
  // Screen keys (D-10: mandatory for all screens)
  static const screen = Key('event_command_center_screen');
  static const dayBadge = Key('event_command_center_day_badge');
  static const createEventScreen = Key('create_event_screen');

  // Module cards — unique key per card (no duplicate keys in tree)
  static const ledgerCard = Key('event_ledger_card');

  // Actions
  static const createEventButton = Key('event_create_button');
  static const selectAllButton = Key('event_select_all_button');

  // Sections
  static const spendingHero = Key('event_spending_hero');
  static const addExpenseChip = Key('event_add_expense_chip');

  // Parameterized key for event type picker cards
  static Key eventTypeCard(String typeLabel) =>
      Key('event_type_card_${typeLabel.toLowerCase().replaceAll(' ', '_')}');

  // Settings screen keys (Phase 31)
  static const settingsScreen = Key('event_settings_screen');
  static const settingsBackButton = Key('event_settings_back_button');
  static const infoSection = Key('event_info_section');
  static const dangerSection = Key('event_danger_section');
  static const saveChangesButton = Key('event_save_changes_button');
  static const deleteEventTile = Key('event_delete_tile');
  static const deleteEventDialog = Key('event_delete_dialog');
  static const deleteEventConfirmButton = Key('event_delete_confirm_button');
  static const settingsButton = Key('event_settings_button');

  // Close lifecycle (#723)
  static const closeEventTile = Key('event_close_tile');
  static const closeEventConfirmButton = Key('event_close_confirm_button');
  static const closedBanner = Key('event_closed_banner');

  // Recap screen (#202 Slice 1)
  static const recapScreen = Key('event_recap_screen');
  static const recapBackButton = Key('event_recap_back_button');
  static const recapButton = Key('event_recap_button');
  static const recapFrozenCaption = Key('event_recap_frozen_caption');

  // Shareable recap card (#202 Slice 4 / #722)
  static const recapShareButton = Key('event_recap_share_button');
  static const recapShareSheet = Key('event_recap_share_sheet');
  static const recapShareConfirmButton = Key('event_recap_share_confirm_button');

  // Trip Receipt CSV export (#704 Slice A / #708)
  static const recapExportCsvButton = Key('event_recap_export_csv_button');

  // Trip Receipt PDF export (#704 Slice B / #708)
  static const recapExportPdfButton = Key('event_recap_export_pdf_button');

  // Event-vs-group settle CTA (#202 / #721 deferred item)
  static const recapSettleCta = Key('event_recap_settle_cta');
  static const recapSettleEventButton = Key('event_recap_settle_event_button');
  static const recapSettleGroupButton = Key('event_recap_settle_group_button');
}
