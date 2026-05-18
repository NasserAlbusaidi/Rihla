import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/r_amount.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import '../utils/localized_category_name.dart';

/// T3.L — v1 minimal ledger search. Client-side substring filter across
/// description / category / payer (expenses) and payer / recipient / note
/// (settlements). The timeline data is already in memory in [LedgerScreen];
/// the sheet operates on the snapshot passed in.
Future<void> showLedgerSearchSheet(
  BuildContext context, {
  required List<Expense> expenses,
  required List<Settlement> settlements,
  required Map<String, String> expensePayerDisplayNames,
  required Map<String, ({String payerName, String recipientName})>
  settlementDisplayNames,
  required String groupId,
  required String eventId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.scaffoldBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _LedgerSearchSheet(
      expenses: expenses,
      settlements: settlements,
      expensePayerDisplayNames: expensePayerDisplayNames,
      settlementDisplayNames: settlementDisplayNames,
      groupId: groupId,
      eventId: eventId,
    ),
  );
}

class _LedgerSearchSheet extends StatefulWidget {
  const _LedgerSearchSheet({
    required this.expenses,
    required this.settlements,
    required this.expensePayerDisplayNames,
    required this.settlementDisplayNames,
    required this.groupId,
    required this.eventId,
  });

  final List<Expense> expenses;
  final List<Settlement> settlements;
  final Map<String, String> expensePayerDisplayNames;
  final Map<String, ({String payerName, String recipientName})>
  settlementDisplayNames;
  final String groupId;
  final String eventId;

  @override
  State<_LedgerSearchSheet> createState() => _LedgerSearchSheetState();
}

class _LedgerSearchSheetState extends State<_LedgerSearchSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final next = _controller.text.trim();
      if (next != _query) setState(() => _query = next);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final viewInsets = mediaQuery.viewInsets.bottom;
    final maxHeight = mediaQuery.size.height * 0.9;
    final results = _filter(
      widget.expenses,
      widget.settlements,
      _query,
      expensePayerDisplayNames: widget.expensePayerDisplayNames,
      settlementDisplayNames: widget.settlementDisplayNames,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              _GrabHandle(),
              const SizedBox(height: 12),
              _SearchBar(
                controller: _controller,
                focusNode: _focusNode,
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _Results(
                  query: _query,
                  results: results,
                  groupId: widget.groupId,
                  eventId: widget.eventId,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GrabHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: context.colors.rule2,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colors.inputFill,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    Iconsax.search_normal,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: LedgerKeys.searchField,
                      controller: controller,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: l10n.ledgerSearchHint,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                      style: AppTypography.sans(
                        fontSize: 15,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  if (controller.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        HapticService.lightClick();
                        controller.clear();
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Icon(
                        Iconsax.close_circle,
                        size: 18,
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onClose,
            child: Text(
              l10n.commonCancel,
              style: AppTypography.sans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.query,
    required this.results,
    required this.groupId,
    required this.eventId,
  });

  final String query;
  final List<_SearchHit> results;
  final String groupId;
  final String eventId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (query.isEmpty) {
      return _Hint(
        icon: Iconsax.search_normal,
        title: l10n.ledgerSearchTitle,
        message: l10n.ledgerSearchPromptMessage,
      );
    }
    if (results.isEmpty) {
      return _Hint(
        icon: Iconsax.receipt_minus,
        title: l10n.ledgerSearchNoMatchesTitle,
        message: l10n.ledgerSearchNoMatchesMessage(query),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _ResultRow(
        hit: results[index],
        onTap: () {
          final hit = results[index];
          if (hit is _ExpenseHit) {
            HapticService.lightClick();
            Navigator.of(context).pop();
            GoRouter.of(context).push(
              '/group/$groupId/event/$eventId/ledger/edit/${hit.expense.id}',
            );
          }
        },
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.hit, required this.onTap});

  final _SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: context.shadows.flat,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.inputFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                hit.leadingIcon,
                size: 18,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hit.title(l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hit.subtitle(l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.sans(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            RAmount(value: hit.amount, currency: hit.currency, size: 14),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: colors.textSecondary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.sans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.sans(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────── Filter

sealed class _SearchHit {
  IconData get leadingIcon;
  String title(AppLocalizations l10n);
  String subtitle(AppLocalizations l10n);
  Decimal get amount;
  String get currency;
  DateTime get date;
}

final class _ExpenseHit extends _SearchHit {
  _ExpenseHit(this.expense, this.payerDisplay);
  final Expense expense;
  final String? payerDisplay;

  @override
  IconData get leadingIcon => Iconsax.receipt_item;

  @override
  String title(AppLocalizations l10n) {
    if (expense.description?.trim().isNotEmpty == true) {
      return expense.description!.trim();
    }
    if (expense.categoryId != null || expense.categoryName != null) {
      return localizedCategoryName(
        id: expense.categoryId,
        fallbackName: expense.categoryName,
        l10n: l10n,
      );
    }
    return l10n.ledgerExpenseFallback;
  }

  @override
  String subtitle(AppLocalizations l10n) {
    final parts = <String>[
      if (expense.categoryId != null || expense.categoryName != null)
        localizedCategoryName(
          id: expense.categoryId,
          fallbackName: expense.categoryName,
          l10n: l10n,
        ),
      if (payerDisplay != null) l10n.ledgerPaidBy(payerDisplay!),
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  @override
  Decimal get amount => expense.amount;
  @override
  String get currency => expense.currency;
  @override
  DateTime get date => expense.createdAt;
}

final class _SettlementHit extends _SearchHit {
  _SettlementHit(this.settlement, this.payerDisplay, this.recipientDisplay);
  final Settlement settlement;
  final String? payerDisplay;
  final String? recipientDisplay;

  @override
  IconData get leadingIcon => Iconsax.arrow_swap;

  @override
  String title(AppLocalizations l10n) {
    final payer = payerDisplay ?? l10n.ledgerSomeone;
    final recipient = recipientDisplay ?? l10n.ledgerSomeone;
    return '$payer → $recipient';
  }

  @override
  String subtitle(AppLocalizations l10n) =>
      settlement.note?.trim().isNotEmpty == true
      ? settlement.note!.trim()
      : l10n.ledgerSettlementFallback;
  @override
  Decimal get amount => settlement.amount;
  @override
  String get currency => 'OMR';
  @override
  DateTime get date => settlement.settledAt;
}

/// Public for testing. Case-insensitive substring match.
List<_SearchHit> _filter(
  List<Expense> expenses,
  List<Settlement> settlements,
  String query, {
  Map<String, String> expensePayerDisplayNames = const {},
  Map<String, ({String payerName, String recipientName})>
      settlementDisplayNames =
      const {},
}) {
  if (query.isEmpty) return const [];
  final needle = query.toLowerCase();

  bool hitsExpense(Expense e) {
    final haystacks = [
      e.description,
      e.categoryName,
      e.payerName,
      expensePayerDisplayNames[e.id],
    ];
    return haystacks.any((s) => s != null && s.toLowerCase().contains(needle));
  }

  bool hitsSettlement(Settlement s) {
    final haystacks = [
      s.payerName,
      s.recipientName,
      settlementDisplayNames[s.id]?.payerName,
      settlementDisplayNames[s.id]?.recipientName,
      s.note,
    ];
    return haystacks.any((v) => v != null && v.toLowerCase().contains(needle));
  }

  final hits = <_SearchHit>[
    for (final expense in expenses.where(hitsExpense))
      _ExpenseHit(expense, expensePayerDisplayNames[expense.id]),
    for (final settlement in settlements.where(hitsSettlement))
      _SettlementHit(
        settlement,
        settlementDisplayNames[settlement.id]?.payerName ??
            settlement.payerName,
        settlementDisplayNames[settlement.id]?.recipientName ??
            settlement.recipientName,
      ),
  ]..sort((a, b) => b.date.compareTo(a.date));

  return hits;
}

@visibleForTesting
List<Object> debugFilter(
  List<Expense> expenses,
  List<Settlement> settlements,
  String query,
) {
  return _filter(expenses, settlements, query)
      .map<Object>(
        (hit) => switch (hit) {
          _ExpenseHit(:final expense) => expense,
          _SettlementHit(:final settlement) => settlement,
        },
      )
      .toList();
}
