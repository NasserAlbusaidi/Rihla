import 'package:flutter/material.dart';

abstract final class EventKeys {
  // Screen keys (D-10: mandatory for all screens)
  static const screen = Key('event_command_center_screen');
  static const createEventScreen = Key('create_event_screen');

  // Tabbed event view (#758)
  static const tabBar = Key('event_tab_bar');
  static const tabExpenses = Key('event_tab_expenses');
  static const tabSettleUp = Key('event_tab_settle_up');
  static const tabActivity = Key('event_tab_activity');
  static const tabRecap = Key('event_tab_recap');
  static const balanceHeader = Key('event_balance_header');
  static const headerCompactAmount = Key('event_header_compact_amount');
  static const addExpenseFab = Key('event_add_expense_fab');
  static const searchButton = Key('event_search_button');

  // Actions
  static const createEventButton = Key('event_create_button');
  static const selectAllButton = Key('event_select_all_button');

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
  // #708 close-wiring: closed-event banner surfaces the Trip Receipt export.
  static const closedBannerViewReceipt = Key('event_closed_banner_view_receipt');
  // #811: open-event counterpart to the closed banner — a labelled recap entry
  // (replaces the tooltip-only header cup).
  static const openRecapBanner = Key('event_open_recap_banner');
  static const openRecapBannerViewRecap = Key('event_open_recap_view_recap');

  // Recap screen (#202 Slice 1)
  static const recapScreen = Key('event_recap_screen');
  static const recapBackButton = Key('event_recap_back_button');
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
