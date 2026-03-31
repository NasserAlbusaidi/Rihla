import 'package:animations/animations.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/smart_module_card.dart';
import '../keys/event_keys.dart';
import '../../activity/screens/activity_feed_screen.dart';
import '../../gear/models/gear_item_model.dart';
import '../../gear/providers/gear_provider.dart';
import '../../gear/screens/gear_screen.dart';
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

/// 2x3 grid of module cards for an event hub.
///
/// Fixed order: Ledger, Gear, Logistics, Vault, Activity, Memories.
/// Activity card always appears (position 5).
/// Uses AppColorTokens.light for corrected module accent colors.
/// Part of Phase 20 P02 redesign (D-11, D-12, D-13, D-14).
///
/// Phase 22 P03: Each SmartModuleCard is wrapped in OpenContainer for
/// ContainerTransform expand animation to the destination screen (D-05).
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
      _addLedgerCard(cards, expensesAsync, settlementsAsync, eventRef);
    }
    if (showGear) {
      _addGearCard(cards, gearAsync);
    }
    if (showLogistics) {
      _addLogisticsCard(cards, subGroupsAsync);
    }
    if (showVault) {
      _addVaultCard(cards, docsAsync);
    }
    // Activity card always appears (position 5)
    _addActivityCard(cards);
    if (showMemories) {
      _addMemoriesCard(cards);
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
          OpenContainer<void>(
            closedColor: Colors.transparent,
            openColor: AppColorTokens.light.scaffoldBackground,
            closedElevation: 0,
            openElevation: 0,
            closedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                AppSpacingTokens.standard.radiusMedium,
              ),
            ),
            openShape: const RoundedRectangleBorder(),
            transitionDuration: const Duration(milliseconds: 400),
            transitionType: ContainerTransitionType.fade,
            useRootNavigator: false,
            closedBuilder: (context, openContainer) => SmartModuleCard(
              key: cards[i].widgetKey,
              icon: cards[i].icon,
              title: cards[i].title,
              description: cards[i].description,
              color: cards[i].color,
              onTap: openContainer,
              summaryText: cards[i].summaryText,
              actionText: cards[i].actionText,
              isEmpty: cards[i].isEmpty,
            ),
            openBuilder: (context, _) => cards[i].screenBuilder(),
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
      color: AppColorTokens.light.moduleLedger,
      screenBuilder: () => LedgerScreen(groupId: groupId, eventId: eventId),
      summaryText: ledgerSummary,
      isEmpty: ledgerEmpty,
    ));
  }

  void _addGearCard(
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
      color: AppColorTokens.light.moduleGear,
      screenBuilder: () => GearScreen(groupId: groupId, eventId: eventId),
      summaryText: gearSummary,
      actionText: gearAction,
      isEmpty: gearEmpty,
    ));
  }

  void _addLogisticsCard(
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
      color: AppColorTokens.light.moduleLogistics,
      screenBuilder: () =>
          LogisticsScreen(groupId: groupId, eventId: eventId),
      summaryText: logisticsSummary,
      isEmpty: logisticsEmpty,
    ));
  }

  void _addVaultCard(
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
      color: AppColorTokens.light.moduleVault,
      screenBuilder: () => VaultScreen(groupId: groupId, eventId: eventId),
      summaryText: vaultSummary,
      isEmpty: vaultEmpty,
    ));
  }

  void _addActivityCard(List<_ModuleCardConfig> cards) {
    cards.add(_ModuleCardConfig(
      widgetKey: EventKeys.activityCard,
      icon: Iconsax.activity,
      title: 'Activity',
      description: 'Timeline logs',
      color: AppColorTokens.light.moduleActivity,
      screenBuilder: () =>
          ActivityFeedScreen(groupId: groupId, eventId: eventId),
      isEmpty: true,
    ));
  }

  void _addMemoriesCard(List<_ModuleCardConfig> cards) {
    cards.add(_ModuleCardConfig(
      widgetKey: EventKeys.memoriesCard,
      icon: Iconsax.gallery,
      title: 'Memories',
      description: 'Capture and share photos from your event',
      color: AppColorTokens.light.moduleMemories,
      screenBuilder: () =>
          MemoriesScreen(groupId: groupId, eventId: eventId),
      isEmpty: true,
    ));
  }
}

/// Internal config for building module cards in fixed-order grid.
///
/// [screenBuilder] provides the destination screen widget for OpenContainer.
/// The old [onTap] field is removed — OpenContainer's closedBuilder calls
/// [openContainer] directly for the ContainerTransform animation.
class _ModuleCardConfig {
  final Key? widgetKey;
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  /// Returns the destination screen for OpenContainer's openBuilder.
  final Widget Function() screenBuilder;

  final String? summaryText;
  final String? actionText;
  final bool isEmpty;

  const _ModuleCardConfig({
    this.widgetKey,
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.screenBuilder,
    this.summaryText,
    this.actionText,
    this.isEmpty = true,
  });
}
