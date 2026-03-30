import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/smart_module_card.dart';
import '../keys/event_keys.dart';
import '../../gear/models/gear_item_model.dart';
import '../../gear/providers/gear_provider.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/models/settlement_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../logistics/models/sub_group_model.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../../vault/models/document_model.dart';
import '../../vault/providers/document_provider.dart';
import '../models/event_model.dart';

/// Priority-sorted list of module cards for an event hub.
///
/// Uses string IDs + EventRef-based Firestore providers for all data.
/// Receives [EventModules?] from [EventCommandCenter] which already has the
/// event from its provider lookup — no redundant provider watch here.
/// If [modules] is null, all modules are shown.
/// Part of the D-14 big-bang constructor migration.
class EventModuleList extends ConsumerWidget {
  final String groupId;
  final String eventId;
  final EventModules? modules;

  const EventModuleList({
    super.key,
    required this.groupId,
    required this.eventId,
    this.modules,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventRef = (groupId: groupId, eventId: eventId);

    // Determine which modules are enabled (null modules = show all)
    final showLedger = modules?.ledger ?? true;
    final showGear = modules?.gear ?? true;
    final showLogistics = modules?.logistics ?? true;
    final showVault = modules?.vault ?? true;
    final showMemories = modules?.memories ?? true;

    // Always watch core providers — needed for Ledger card.
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));

    // Conditionally watch module-specific providers.
    final gearAsync =
        showGear ? ref.watch(eventGearItemsProvider(eventRef)) : null;
    final subGroupsAsync =
        showLogistics ? ref.watch(eventSubGroupsProvider(eventRef)) : null;
    final docsAsync =
        showVault ? ref.watch(eventDocumentsProvider(eventRef)) : null;

    // Build module card configs.
    final cards = <_ModuleCardConfig>[];

    // --- Ledger ---
    if (showLedger) {
      _addLedgerCard(cards, expensesAsync, settlementsAsync, context, eventRef);
    }

    // --- Gear ---
    if (showGear) {
      _addGearCard(cards, gearAsync, context);
    }

    // --- Logistics ---
    if (showLogistics) {
      _addLogisticsCard(cards, subGroupsAsync, context);
    }

    // --- Vault ---
    if (showVault) {
      _addVaultCard(cards, docsAsync, context);
    }

    // --- Memories ---
    if (showMemories) {
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
    EventRef eventRef,
  ) {
    final expenses = expensesAsync.valueOrNull ?? [];

    // We need the currency — derive from event ref via a default.
    // The currency is displayed in the summary but we don't have direct access
    // here; use a placeholder that the parent could pass, but for now we'll
    // just show count as the summary without currency formatting.
    // A null-safe fallback: show expense count only.
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
      // Use OMR as default currency display for module card summary
      ledgerSummary =
          '$count expense${count != 1 ? "s" : ""} \u00b7 ${AppFormatters.formatCurrency(totalSpent, 'OMR')}';
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
    context.push('/group/$groupId/event/$eventId/ledger');
  }

  void _openGear(BuildContext context) {
    context.push('/group/$groupId/event/$eventId/gear');
  }

  void _openLogistics(BuildContext context) {
    context.push('/group/$groupId/event/$eventId/logistics');
  }

  void _openVault(BuildContext context) {
    context.push('/group/$groupId/event/$eventId/vault');
  }

  void _openMemories(BuildContext context) {
    context.push('/group/$groupId/event/$eventId/memories');
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
