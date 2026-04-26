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
import '../../ledger/models/expense_model.dart';
import '../../ledger/models/settlement_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../models/event_model.dart';

/// List of module cards for an event hub.
///
/// Phase 39 strip reduced this to Ledger + Activity. Cards navigate via
/// GoRouter so deep links and redirect guards work correctly.
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

    final showLedger = modules?.ledger ?? true;

    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));

    final cards = <_ModuleCardConfig>[];

    if (showLedger) {
      _addLedgerCard(context, cards, expensesAsync, settlementsAsync, eventRef);
    }
    _addActivityCard(context, cards);

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
          '$count expense${count != 1 ? "s" : ""} · ${AppFormatters.formatCurrency(totalSpent, 'OMR')}';
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
}

/// Internal config for building module cards.
class _ModuleCardConfig {
  final Key? widgetKey;
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  /// GoRouter path for navigation.
  final String routePath;

  final String? summaryText;
  final bool isEmpty;

  const _ModuleCardConfig({
    this.widgetKey,
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.routePath,
    this.summaryText,
    this.isEmpty = true,
  });
}
