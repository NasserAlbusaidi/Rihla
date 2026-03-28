import 'package:flutter/material.dart';

abstract final class EventKeys {
  // Screen keys (D-10: mandatory for all screens)
  static const screen = Key('event_command_center_screen');
  static const createEventScreen = Key('create_event_screen');
  static const eventTypePickerScreen = Key('event_type_picker_screen');
  static const eventExpenseHeroScreen = Key('event_expense_hero_screen');

  // Module cards — unique key per card (no duplicate keys in tree)
  static const ledgerCard = Key('event_ledger_card');
  static const gearCard = Key('event_gear_card');
  static const logisticsCard = Key('event_logistics_card');
  static const vaultCard = Key('event_vault_card');
  static const memoriesCard = Key('event_memories_card');
  static const activityCard = Key('event_activity_card');

  // Actions
  static const addExpenseFab = Key('event_add_expense_fab');

  // Sections
  static const spendingHero = Key('event_spending_hero');
  static const moduleList = Key('event_module_list');

  // Parameterized keys for event list items
  static Key eventCard(String eventId) => Key('event_card_$eventId');
}
