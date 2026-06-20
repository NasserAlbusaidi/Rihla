import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_icon_button.dart';
import '../keys/event_keys.dart';
import '../models/event_recap.dart';
import '../providers/event_provider.dart';
import '../providers/event_recap_provider.dart';

/// On-demand event recap (#202 Slice 1): total spent + the current user's
/// paid / share / settlements / net, all per currency. Read-only, computed
/// live from the ledger — no event-closure state or snapshot yet.
class EventRecapScreen extends ConsumerWidget {
  const EventRecapScreen({
    super.key,
    required this.groupId,
    required this.eventId,
  });

  final String groupId;
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventRef = (groupId: groupId, eventId: eventId);
    final eventAsync = ref.watch(eventDetailProvider(eventRef));

    return Scaffold(
      key: EventKeys.recapScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: eventAsync.when(
          loading: () => _wrap(context, const [Center(child: Padding(
            padding: EdgeInsets.only(top: 48),
            child: CircularProgressIndicator(),
          ))]),
          error: (_, _) => _notFound(context),
          data: (event) {
            if (event == null) return _notFound(context);
            final recap = ref.watch(eventRecapProvider(eventRef));
            if (recap.isEmpty) return _empty(context);
            return _wrap(context, _content(context, recap));
          },
        ),
      ),
    );
  }

  /// Scrollable column with the standard back button + 24px gutters.
  Widget _wrap(BuildContext context, List<Widget> children) {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: context.spacing.space24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: context.spacing.space16),
            _backButton(context),
            SizedBox(height: context.spacing.space16),
            ...children,
            SizedBox(height: context.spacing.space24),
          ],
        ),
      ),
    );
  }

  Widget _backButton(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: RIconButton(
        key: EventKeys.recapBackButton,
        variant: RIconButtonVariant.ghost,
        icon: Directionality.of(context) == TextDirection.rtl
            ? Iconsax.arrow_right
            : Iconsax.arrow_left,
        // Nested route → canPop() is always true; bare pop reaches the hub
        // (#243 nested back-guard convention).
        onTap: () {
          if (GoRouter.of(context).canPop()) GoRouter.of(context).pop();
        },
      ),
    );
  }

  List<Widget> _content(BuildContext context, EventRecap recap) {
    final currencies = recap.userNetByCurrency.keys.toList();
    return [
      Text(
        recap.eventName,
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: context.colors.textPrimary,
        ),
      ),
      SizedBox(height: context.spacing.space4),
      Text(
        context.l10n.recapPeopleExpenses(
          recap.participantCount,
          recap.expenseCount,
        ),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: context.colors.textSecondary,
        ),
      ),
      SizedBox(height: context.spacing.space24),

      // Total spent (per currency).
      _sectionLabel(context, context.l10n.recapTotalSpent),
      for (final entry in recap.totalSpentByCurrency.entries)
        _amountRow(context, entry.key, entry.value, entry.key),

      // The current user's story (per currency), reconciling net = paid − share + settled.
      if (currencies.isNotEmpty) ...[
        SizedBox(height: context.spacing.space24),
        _sectionLabel(context, context.l10n.recapYouTitle),
        for (final ccy in currencies) ..._userBlock(context, recap, ccy),
      ],
    ];
  }

  /// One currency's user rows: paid / share / settlements (each only when
  /// non-zero) + net (always), so a square-but-active spender is still shown.
  List<Widget> _userBlock(BuildContext context, EventRecap recap, String ccy) {
    final paid = recap.userPaidByCurrency[ccy] ?? Decimal.zero;
    final share = recap.userShareByCurrency[ccy] ?? Decimal.zero;
    final settled = recap.userSettledByCurrency[ccy] ?? Decimal.zero;
    final net = recap.userNetByCurrency[ccy] ?? Decimal.zero;
    return [
      if (paid != Decimal.zero)
        _amountRow(context, context.l10n.recapYouPaid, paid, ccy),
      if (share != Decimal.zero)
        _amountRow(context, context.l10n.recapYourShare, share, ccy),
      if (settled != Decimal.zero)
        _amountRow(context, context.l10n.recapSettlements, settled, ccy,
            sign: true),
      _amountRow(context, context.l10n.recapNet, net, ccy, sign: true),
    ];
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: context.spacing.space8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: context.colors.textSecondary,
        ),
      ),
    );
  }

  Widget _amountRow(
    BuildContext context,
    String label,
    Decimal value,
    String currency, {
    bool sign = false,
  }) {
    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: context.spacing.space8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          RAmount(value: value, currency: currency, sign: sign, size: 15),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return _wrap(context, [
      const SizedBox(height: 24),
      EmptyStateView(
        icon: Iconsax.receipt_item,
        title: context.l10n.recapEmptyTitle,
        message: context.l10n.recapEmptyMessage,
      ),
    ]);
  }

  Widget _notFound(BuildContext context) {
    return _wrap(context, [
      const SizedBox(height: 24),
      EmptyStateView(
        icon: Iconsax.warning_2,
        title: context.l10n.eventNotFound,
        message: context.l10n.recapEmptyMessage,
      ),
    ]);
  }
}
