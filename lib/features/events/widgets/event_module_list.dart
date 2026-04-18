import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/tokens/domain_aliases.dart';
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

/// 2x3 grid of module cards for an event hub.
///
/// Fixed order: Ledger, Gear, Logistics, Vault, Activity, Memories.
/// Activity card always appears (position 5).
/// Uses AppColorTokens.light for corrected module accent colors.
/// Part of Phase 20 P02 redesign (D-11, D-12, D-13, D-14).
///
/// Phase 22 P03 (updated): Cards navigate via GoRouter instead of
/// OpenContainer, so deep links and redirect guards work correctly.
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

    // Build module card configs in fixed order (D-13: no priority sorting).
    final cards = <_ModuleCardConfig>[];

    // Fixed order: Ledger → Gear → Logistics → Vault → Activity → Memories
    if (showLedger) {
      _addLedgerCard(context, cards, expensesAsync, settlementsAsync, eventRef);
    }
    if (showGear) {
      _addGearCard(context, cards, gearAsync);
    }
    if (showLogistics) {
      _addLogisticsCard(context, cards, subGroupsAsync);
    }
    if (showVault) {
      _addVaultCard(context, cards, docsAsync);
    }
    // Activity card always appears (position 5)
    _addActivityCard(context, cards);
    if (showMemories) {
      _addMemoriesCard(context, cards);
    }

    return GridView.count(
      key: EventKeys.moduleGrid,
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 2.0,
      children: [
        for (int i = 0; i < cards.length; i++)
          SmartModuleCard(
            key: cards[i].widgetKey,
            icon: cards[i].icon,
            title: cards[i].title,
            description: cards[i].description,
            color: cards[i].color,
            onTap: () => context.push(cards[i].routePath),
            summaryText: cards[i].summaryText,
            actionText: cards[i].actionText,
            isEmpty: cards[i].isEmpty,
          )
              .animate()
              .fadeIn(delay: (80 * i).ms, duration: 400.ms)
              .slideY(
                begin: 0.1,
                end: 0,
                delay: (80 * i).ms,
                duration: 400.ms,
              ),
      ],
    );
  }

  void _addLedgerCard(
    BuildContext context,
    List<_ModuleCardConfig> cards,
    AsyncValue<List<Expense>> expensesAsync,
    AsyncValue<List<Settlement>> settlementsAsync,
    EventRef eventRef,
  ) {
    final expenses = expensesAsync.valueOrNull ?? [];

    final totalSpent = expenses.fold<Decimal>(
      Decimal.zero,
      (sum, e) => sum + e.amount,
    );

    String? ledgerSummary;
    final bool ledgerEmpty = expenses.isEmpty;

    if (expenses.isNotEmpty) {
      final count = expenses.length;
      ledgerSummary =
          '$count expense${count != 1 ? "s" : ""} \u00b7 ${AppFormatters.formatCurrency(totalSpent, 'OMR')}';
    }

    cards.add(_ModuleCardConfig(
      widgetKey: EventKeys.ledgerCard,
      icon: Iconsax.wallet_3,
      title: 'Ledger',
      description: 'Track shared expenses and split costs fairly',
      color: context.colors.moduleLedger,
      routePath: '/group/$groupId/event/$eventId/ledger',
      summaryText: ledgerSummary,
      isEmpty: ledgerEmpty,
    ));
  }

  void _addGearCard(
    BuildContext context,
    List<_ModuleCardConfig> cards,
    AsyncValue<List<GearItem>>? gearAsync,
  ) {
    final gearItems = gearAsync?.valueOrNull ?? [];
    final gearEmpty = gearItems.isEmpty;
    String? gearSummary;
    String? gearAction;

    if (gearItems.isNotEmpty) {
      final total = gearItems.length;
      final claimed = gearItems.where((i) => i.assignedTo != null).length;
      final packed = gearItems.where((i) => i.isPacked).length;
      final unclaimed = total - claimed;

      if (unclaimed > 0) {
        gearAction =
            '$unclaimed item${unclaimed != 1 ? "s" : ""} still need someone';
      } else {
        gearSummary = '$total items \u00b7 $packed packed';
      }
    }

    cards.add(_ModuleCardConfig(
      widgetKey: EventKeys.gearCard,
      icon: Iconsax.bag_2,
      title: 'Gear',
      description: 'Create a shared packing list and claim items',
      color: context.colors.moduleGear,
      routePath: '/group/$groupId/event/$eventId/gear',
      summaryText: gearSummary,
      actionText: gearAction,
      isEmpty: gearEmpty,
    ));
  }

  void _addLogisticsCard(
    BuildContext context,
    List<_ModuleCardConfig> cards,
    AsyncValue<List<SubGroup>>? subGroupsAsync,
  ) {
    final subGroups = subGroupsAsync?.valueOrNull ?? [];
    final logisticsEmpty = subGroups.isEmpty;
    String? logisticsSummary;

    if (subGroups.isNotEmpty) {
      final cars = subGroups.where((g) => g.type == SubGroupType.car).length;
      final rooms = subGroups.where((g) => g.type == SubGroupType.room).length;
      final parts = <String>[];
      if (cars > 0) parts.add('$cars car${cars != 1 ? "s" : ""}');
      if (rooms > 0) parts.add('$rooms room${rooms != 1 ? "s" : ""}');
      logisticsSummary = parts.join(' \u00b7 ');
    }

    cards.add(_ModuleCardConfig(
      widgetKey: EventKeys.logisticsCard,
      icon: Iconsax.car,
      title: 'Logistics',
      description: 'Organize cars, rooms, and teams for your group',
      color: context.colors.moduleLogistics,
      routePath: '/group/$groupId/event/$eventId/logistics',
      summaryText: logisticsSummary,
      isEmpty: logisticsEmpty,
    ));
  }

  void _addVaultCard(
    BuildContext context,
    List<_ModuleCardConfig> cards,
    AsyncValue<List<Document>>? docsAsync,
  ) {
    final docs = docsAsync?.valueOrNull ?? [];
    final vaultEmpty = docs.isEmpty;
    String? vaultSummary;

    if (docs.isNotEmpty) {
      vaultSummary =
          '${docs.length} document${docs.length != 1 ? "s" : ""} uploaded';
    }

    cards.add(_ModuleCardConfig(
      widgetKey: EventKeys.vaultCard,
      icon: Iconsax.document_text,
      title: 'Vault',
      description: 'Store tickets, permits, and trip documents',
      color: context.colors.moduleVault,
      routePath: '/group/$groupId/event/$eventId/vault',
      summaryText: vaultSummary,
      isEmpty: vaultEmpty,
    ));
  }

  void _addActivityCard(BuildContext context, List<_ModuleCardConfig> cards) {
    cards.add(_ModuleCardConfig(
      widgetKey: EventKeys.activityCard,
      icon: Iconsax.activity,
      title: 'Activity',
      description: 'Timeline logs',
      color: context.colors.moduleActivity,
      routePath: '/group/$groupId/event/$eventId/activity',
      isEmpty: true,
    ));
  }

  void _addMemoriesCard(BuildContext context, List<_ModuleCardConfig> cards) {
    cards.add(_ModuleCardConfig(
      widgetKey: EventKeys.memoriesCard,
      icon: Iconsax.gallery,
      title: 'Memories',
      description: 'Capture and share photos from your event',
      color: context.colors.moduleMemories,
      routePath: '/group/$groupId/event/$eventId/memories',
      isEmpty: true,
    ));
  }
}

/// Internal config for building module cards in fixed-order grid.
///
/// [routePath] is the GoRouter path for the destination screen.
class _ModuleCardConfig {
  final Key? widgetKey;
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  /// GoRouter path for navigation.
  final String routePath;

  final String? summaryText;
  final String? actionText;
  final bool isEmpty;

  const _ModuleCardConfig({
    this.widgetKey,
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.routePath,
    this.summaryText,
    this.actionText,
    this.isEmpty = true,
  });
}
