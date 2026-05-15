import 'package:flutter/material.dart';

abstract final class EventKeys {
  // Screen keys (D-10: mandatory for all screens)
  static const screen = Key('event_command_center_screen');
  static const dayBadge = Key('event_command_center_day_badge');
  static const createEventScreen = Key('create_event_screen');
  static const eventTypePickerScreen = Key('event_type_picker_screen');
  static const eventTypePickerTitle = Key('event_type_picker_title');
  static const eventExpenseHeroScreen = Key('event_expense_hero_screen');

  // Module cards — unique key per card (no duplicate keys in tree)
  static const ledgerCard = Key('event_ledger_card');
  static const activityCard = Key('event_activity_card');

  // Actions
  static const addExpenseFab = Key('event_add_expense_fab');
  static const createEventButton = Key('event_create_button');
  static const selectAllButton = Key('event_select_all_button');

  // Sections
  static const spendingHero = Key('event_spending_hero');
  static const moduleList = Key('event_module_list');
  static const modulesSection = Key('event_modules_section');
  static const moduleGrid = Key('event_module_grid');
  static const expenseHeroTotal = Key('event_expense_hero_total');
  static const addExpenseChip = Key('event_add_expense_chip');

  // Event type picker card keys
  static const eventTypeTripOption = Key('event_type_trip_option');
  static const eventTypeCampingOption = Key('event_type_camping_option');
  static const eventTypeDayOutOption = Key('event_type_day_out_option');
  static const eventTypeDinnerOption = Key('event_type_dinner_option');
  static const eventTypeCustomOption = Key('event_type_custom_option');

  // Module toggle row keys (CreateEventScreen Custom type)
  static const moduleLedgerToggle = Key('event_module_ledger_toggle');

  // Parameterized keys for event list items
  static Key eventCard(String eventId) => Key('event_card_$eventId');

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
}
