import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/types/event_ref.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../shared/widgets/smart_module_card.dart';
import '../keys/event_keys.dart';
import '../../gear/models/gear_item_model.dart';
import '../../gear/providers/gear_provider.dart';
import '../../gear/screens/gear_screen.dart';
import '../../groups/models/group_model.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/models/settlement_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../ledger/screens/ledger_screen.dart';
import '../../logistics/models/sub_group_model.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../../logistics/screens/logistics_screen.dart';
import '../../memories/screens/memories_screen.dart';
import '../../vault/models/document_model.dart';
import '../../vault/providers/document_provider.dart';
import '../../vault/screens/vault_screen.dart';
import '../models/event_model.dart';

/// Priority-sorted list of module cards for an event hub.
///
/// Uses EventRef-based Firestore providers for all data.
/// No Trip facade — part of bridge removal in Plan 04-05.
/// Cards are filtered by [event.modules] booleans — only enabled
/// modules render a card. This supports Custom events with arbitrary
/// module selections per D-14.
class EventModuleList extends ConsumerWidget {
  final Event event;
  final Group group;
  final EventRef eventRef;

  const EventModuleList({
    super.key,
    required this.event,
    required this.group,
    required this.eventRef,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Always watch core providers — needed for Ledger card.
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));

    // Conditionally watch module-specific providers.
    final gearAsync = event.modules.gear
        ? ref.watch(eventGearItemsProvider(eventRef))
        : null;
    final subGroupsAsync = event.modules.logistics
        ? ref.watch(eventSubGroupsProvider(eventRef))
        : null;
    final docsAsync = event.modules.vault
        ? ref.watch(eventDocumentsProvider(eventRef))
        : null;

    // Build module card configs.
    final cards = <_ModuleCardConfig>[];

    // --- Ledger (conditional on event.modules.ledger — Custom type can toggle off) ---
    if (event.modules.ledger) {
      _addLedgerCard(cards, expensesAsync, settlementsAsync, context);
    }

    // --- Gear ---
    if (event.modules.gear) {
      _addGearCard(cards, gearAsync, context);
    }

    // --- Logistics ---
    if (event.modules.logistics) {
      _addLogisticsCard(cards, subGroupsAsync, context);
    }

    // --- Vault ---
    if (event.modules.vault) {
      _addVaultCard(cards, docsAsync, context);
    }

    // --- Memories ---
    if (event.modules.memories) {
      _addMemoriesCard(cards, context);
    }

    // Sort by priority (highest first).
    cards.sort((a, b) => b.priority.compareTo(a.priority));

    return Column(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          SmartModuleCard(
            key: cards[i].widgetKey,
            icon: cards[i].icon,
            title: cards[i].title,
            description: cards[i].description,
            color: cards[i].color,
            onTap: cards[i].onTap,
            summaryText: cards[i].summaryText,
            actionText: cards[i].actionText,
            priority: cards[i].priority,
            isEmpty: cards[i].isEmpty,
          )
              .animate()
              .fadeIn(delay: (100 * i).ms, duration: 400.ms)
              .slideY(
                begin: 0.1,
                end: 0,
                delay: (100 * i).ms,
                duration: 400.ms,
              ),
        ],
      ],
    );
  }

  void _addLedgerCard(
    List<_ModuleCardConfig> cards,
    AsyncValue<List<Expense>> expensesAsync,
    AsyncValue<List<Settlement>> settlementsAsync,
    BuildContext context,
  ) {
    final expenses = expensesAsync.valueOrNull ?? [];
    final totalSpent = expenses.fold<Decimal>(
      Decimal.zero,
      (sum, e) => sum + e.amount,
    );

    String? ledgerSummary;
    String? ledgerAction;
    int ledgerPriority = 10;
    final bool ledgerEmpty = expenses.isEmpty;

    if (expenses.isNotEmpty) {
      final count = expenses.length;
      ledgerSummary =
          '$count expense${count != 1 ? "s" : ""} \u00b7 ${AppFormatters.formatCurrency(totalSpent, event.currency)}';
      ledgerPriority = 50;
    }

    cards.add(_ModuleCardConfig(
      widgetKey: EventKeys.ledgerCard,
      icon: Iconsax.wallet_3,
      title: 'Ledger',
      description: 'Track shared expenses and split costs fairly',
      color: AppColors.accentSecondary,
      onTap: () => _openLedger(context),
      summaryText: ledgerSummary,
      actionText: ledgerAction,
      priority: ledgerPriority,
      isEmpty: ledgerEmpty,
    ));
  }

  void _addGearCard(
    List<_ModuleCardConfig> cards,
    AsyncValue<List<GearItem>>? gearAsync,
    BuildContext context,
  ) {
    final gearItems = gearAsync?.valueOrNull ?? [];
    final gearEmpty = gearItems.isEmpty;
    String? gearSummary;
    String? gearAction;
    int gearPriority = 10;

    if (gearItems.isNotEmpty) {
      final total = gearItems.length;
      final claimed = gearItems.where((i) => i.assignedTo != null).length;
      final packed = gearItems.where((i) => i.isPacked).length;
      final unclaimed = total - claimed;

      if (unclaimed > 0) {
        gearAction =
            '$unclaimed item${unclaimed != 1 ? "s" : ""} still need someone';
        gearPriority = 80;
      } else {
        gearSummary = '$total items \u00b7 $packed packed';
        gearPriority = 50;
      }
    }

    cards.add(_ModuleCardConfig(
      widgetKey: EventKeys.gearCard,
      icon: Iconsax.bag_2,
      title: 'Gear',
      description: 'Create a shared packing list and claim items',
      color: (gearAction != null) ? AppColors.amber : AppColors.accentSecondary,
      onTap: () => _openGear(context),
      summaryText: gearSummary,
      actionText: gearAction,
      priority: gearPriority,
      isEmpty: gearEmpty,
    ));
  }

  void _addLogisticsCard(
    List<_ModuleCardConfig> cards,
    AsyncValue<List<SubGroup>>? subGroupsAsync,
    BuildContext context,
  ) {
    final subGroups = subGroupsAsync?.valueOrNull ?? [];
    final logisticsEmpty = subGroups.isEmpty;
    String? logisticsSummary;
    int logisticsPriority = 10;

    if (subGroups.isNotEmpty) {
      final cars = subGroups.where((g) => g.type == SubGroupType.car).length;
      final rooms = subGroups.where((g) => g.type == SubGroupType.room).length;
      final parts = <String>[];
      if (cars > 0) parts.add('$cars car${cars != 1 ? "s" : ""}');
      if (rooms > 0) parts.add('$rooms room${rooms != 1 ? "s" : ""}');
      logisticsSummary = parts.join(' \u00b7 ');
      logisticsPriority = 50;
    }

    cards.add(_ModuleCardConfig(
      widgetKey: EventKeys.logisticsCard,
      icon: Iconsax.car,
      title: 'Logistics',
      description: 'Organize cars, rooms, and teams for your group',
      color: AppColors.sky,
      onTap: () => _openLogistics(context),
      summaryText: logisticsSummary,
      priority: logisticsPriority,
      isEmpty: logisticsEmpty,
    ));
  }

  void _addVaultCard(
    List<_ModuleCardConfig> cards,
    AsyncValue<List<Document>>? docsAsync,
    BuildContext context,
  ) {
    final docs = docsAsync?.valueOrNull ?? [];
    final vaultEmpty = docs.isEmpty;
    String? vaultSummary;
    int vaultPriority = 10;

    if (docs.isNotEmpty) {
      vaultSummary =
          '${docs.length} document${docs.length != 1 ? "s" : ""} uploaded';
      vaultPriority = 50;
    }

    cards.add(_ModuleCardConfig(
      widgetKey: EventKeys.vaultCard,
      icon: Iconsax.document_text,
      title: 'Vault',
      description: 'Store tickets, permits, and trip documents',
      color: AppColors.indigo,
      onTap: () => _openVault(context),
      summaryText: vaultSummary,
      priority: vaultPriority,
      isEmpty: vaultEmpty,
    ));
  }

  void _addMemoriesCard(
    List<_ModuleCardConfig> cards,
    BuildContext context,
  ) {
    cards.add(_ModuleCardConfig(
      widgetKey: EventKeys.memoriesCard,
      icon: Iconsax.gallery,
      title: 'Memories',
      description: 'Capture and share photos from your event',
      color: AppColors.mint,
      onTap: () => _openMemories(context),
      priority: 10,
      isEmpty: true,
    ));
  }

  void _openLedger(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (context) => LedgerScreen(event: event, group: group),
      ),
    );
  }

  void _openGear(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (context) => GearScreen(event: event, group: group),
      ),
    );
  }

  void _openLogistics(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (context) => LogisticsScreen(event: event, group: group),
      ),
    );
  }

  void _openVault(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (context) => VaultScreen(event: event, group: group),
      ),
    );
  }

  void _openMemories(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (context) => MemoriesScreen(event: event, group: group),
      ),
    );
  }
}

/// Internal config for building module cards with priority sorting.
class _ModuleCardConfig {
  final Key? widgetKey;
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;
  final String? summaryText;
  final String? actionText;
  final int priority;
  final bool isEmpty;

  const _ModuleCardConfig({
    this.widgetKey,
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
    this.summaryText,
    this.actionText,
    this.priority = 10,
    this.isEmpty = true,
  });
}
