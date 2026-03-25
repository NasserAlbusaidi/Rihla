import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:decimal/decimal.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../shared/widgets/smart_module_card.dart';
import '../../gear/models/gear_item_model.dart';
import '../../gear/providers/gear_provider.dart';
import '../../gear/screens/gear_screen.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../ledger/screens/ledger_screen.dart';
import '../../logistics/models/sub_group_model.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../../logistics/screens/logistics_screen.dart';
import '../../trip/models/trip_model.dart';
import '../../trip/providers/trip_provider.dart';
import '../../vault/models/document_model.dart';
import '../../vault/providers/document_provider.dart';
import '../../vault/screens/vault_screen.dart';

/// Priority-sorted list of module cards (Ledger, Gear, Logistics, Vault).
///
/// Each card shows live data summaries and action prompts. Cards are sorted
/// by priority so the most actionable module appears first.
class ModuleList extends ConsumerWidget {
  final Trip trip;

  const ModuleList({super.key, required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Gather data for all modules
    final expensesAsync = ref.watch(tripExpensesProvider(trip.id));
    final balancesAsync = ref.watch(tripBalancesProvider(trip.id));
    final currentParticipant = ref.watch(currentParticipantProvider(trip.id));
    final gearAsync = trip.modules.gear
        ? ref.watch(tripGearProvider(trip.id))
        : null;
    final subGroupsAsync = trip.modules.logistics
        ? ref.watch(tripSubGroupsProvider(trip.id))
        : null;
    final docsAsync = trip.modules.docs
        ? ref.watch(tripDocumentsProvider(trip.id))
        : null;

    // Build module card configs with priorities
    final cards = <_ModuleCardConfig>[];

    // --- Ledger (always shown) ---
    _addLedgerCard(cards, expensesAsync, balancesAsync, currentParticipant, context);

    // --- Gear ---
    if (trip.modules.gear) {
      _addGearCard(cards, gearAsync, context);
    }

    // --- Logistics ---
    if (trip.modules.logistics) {
      _addLogisticsCard(cards, subGroupsAsync, context);
    }

    // --- Vault ---
    if (trip.modules.docs) {
      _addVaultCard(cards, docsAsync, context);
    }

    // Sort by priority (highest first)
    cards.sort((a, b) => b.priority.compareTo(a.priority));

    return Column(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          SmartModuleCard(
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
    AsyncValue<List<UserBalance>> balancesAsync,
    Participant? currentParticipant,
    BuildContext context,
  ) {
    final expenses = expensesAsync.valueOrNull ?? [];
    final balances = balancesAsync.valueOrNull;
    final userBalance = balances?.cast<UserBalance?>().firstWhere(
      (b) => b?.participantId == currentParticipant?.id,
      orElse: () => null,
    );
    final net = userBalance?.netBalance ?? Decimal.zero;
    final isDebt = net < Decimal.zero;
    final isOwed = net > Decimal.zero;

    String? ledgerSummary;
    String? ledgerAction;
    int ledgerPriority = 10;
    bool ledgerEmpty = expenses.isEmpty;

    if (expenses.isNotEmpty) {
      final count = expenses.length;
      if (net == Decimal.zero) {
        ledgerSummary = '$count expense${count != 1 ? 's' : ''} \u00b7 All settled';
        ledgerPriority = 50;
      } else if (isDebt) {
        ledgerAction =
            'You owe ${AppFormatters.formatCurrency(net.abs(), trip.currency)}';
        ledgerPriority = 100;
      } else {
        ledgerAction =
            'You are owed ${AppFormatters.formatCurrency(net, trip.currency)}';
        ledgerPriority = 90;
      }
    }

    cards.add(_ModuleCardConfig(
      icon: Iconsax.wallet_3,
      title: 'Ledger',
      description: 'Track shared expenses and split costs fairly',
      color: isDebt
          ? AppColors.rose
          : (isOwed ? AppColors.emerald : AppColors.accentSecondary),
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
            '$unclaimed item${unclaimed != 1 ? 's' : ''} still need someone';
        gearPriority = 80;
      } else {
        gearSummary = '$total items \u00b7 $packed packed';
        gearPriority = 50;
      }
    }

    cards.add(_ModuleCardConfig(
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
      final cars =
          subGroups.where((g) => g.type == SubGroupType.car).length;
      final rooms =
          subGroups.where((g) => g.type == SubGroupType.room).length;
      final parts = <String>[];
      if (cars > 0) parts.add('$cars car${cars != 1 ? 's' : ''}');
      if (rooms > 0) parts.add('$rooms room${rooms != 1 ? 's' : ''}');
      logisticsSummary = parts.join(' \u00b7 ');
      logisticsPriority = 50;
    }

    cards.add(_ModuleCardConfig(
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
          '${docs.length} document${docs.length != 1 ? 's' : ''} uploaded';
      vaultPriority = 50;
    }

    cards.add(_ModuleCardConfig(
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

  void _openLedger(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute(builder: (context) => LedgerScreen(trip: trip)),
    );
  }

  void _openGear(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute(builder: (context) => GearScreen(trip: trip)),
    );
  }

  void _openLogistics(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute(builder: (context) => LogisticsScreen(trip: trip)),
    );
  }

  void _openVault(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute(builder: (context) => VaultScreen(trip: trip)),
    );
  }
}

/// Internal config for building module cards with priority sorting.
class _ModuleCardConfig {
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
