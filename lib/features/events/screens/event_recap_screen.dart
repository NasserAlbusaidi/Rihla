import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/constants/supported_currencies.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/localized_dates.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../../shared/widgets/r_icon_button.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../../shared/widgets/skeleton_primitives.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../ledger/providers/ledger_view_provider.dart';
import '../../ledger/utils/ledger_categories.dart';
import '../keys/event_keys.dart';
import '../models/event_model.dart';
import '../models/event_recap.dart';
import '../providers/event_provider.dart';
import '../providers/event_recap_provider.dart';
import '../widgets/recap_share_sheet.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// On-demand event recap (#202 Slice 1 + #721 Slice 2): total spent, the current
/// user's position, plus the full money summary — biggest expense, top payer,
/// category & payer breakdowns, everyone's net, and a read-only settlement
/// status. All per currency. Read-only. Open events compute live from the
/// ledger; a CLOSED event with a captured snapshot serves the FROZEN spending
/// half (settlement stays live) and shows a "spending frozen" caption (#766).
class EventRecapScreen extends ConsumerWidget {
  const EventRecapScreen({
    super.key,
    required this.groupId,
    required this.eventId,
    this.embedded = false,
  });

  final String groupId;
  final String eventId;

  /// #758: content-only mode for the tabbed event view — skips the Scaffold
  /// and the back button (the tabbed shell owns chrome); the share action
  /// stays in the panel's header row.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventRef = (groupId: groupId, eventId: eventId);
    final eventAsync = ref.watch(eventDetailProvider(eventRef));

    final body = eventAsync.when(
      loading: () => _loadingSkeleton(context),
      error: (_, _) => _notFound(context),
      data: (event) {
        if (event == null) return _notFound(context);
        // #1030: recap + its share/export CTAs render ledgerViewProvider
        // folds — a hard-errored source stream means wrong nets (members: a
        // wrong #249 universe), so gate all three BEFORE the recap fold (an
        // errored expenses stream empties the recap, which would render the
        // misleading _empty state instead). Stale values serve; the
        // first-value window keeps the existing spinner.
        final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
        final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));
        final membersAsync = ref.watch(groupMembersProvider(groupId));
        final sources = [expensesAsync, settlementsAsync, membersAsync];
        if (sources.any((s) => s.hasError && !s.hasValue)) {
          return _dataUnavailable(context, ref, eventRef);
        }
        if (sources.any((s) => s.isLoading && !s.hasValue)) {
          return _loadingSkeleton(context);
        }
        final recap = ref.watch(eventRecapProvider(eventRef));
        if (recap.isEmpty) return _empty(context);
        // Names resolved at the widget (the model carries only ids) via the
        // same memoized ledger pass the recap provider already watches.
        final view = ref.watch(ledgerViewProvider(eventRef));
        final uid = ref.watch(currentUserIdProvider);
        return _wrap(
          context,
          _content(context, recap, view.rosterDisplayNames, uid, event),
          trailing: _shareButton(
            context,
            recap,
            view.rosterDisplayNames,
            event,
          ),
        );
      },
    );
    if (embedded) return body;
    return Scaffold(
      key: EventKeys.recapScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(child: body),
    );
  }

  /// Scrollable column with the standard header (back start, optional [trailing]
  /// at the end — the share action on the data path) + 24px gutters. Embedded
  /// mode drops the back button and, with no trailing action, the whole row.
  Widget _wrap(
    BuildContext context,
    List<Widget> children, {
    Widget? trailing,
  }) {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: context.spacing.space24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: context.spacing.space16),
            if (!embedded || trailing != null)
              Row(
                children: [
                  if (!embedded) _backButton(context),
                  const Spacer(),
                  ?trailing,
                ],
              ),
            SizedBox(height: context.spacing.space16),
            ...children,
            SizedBox(height: context.spacing.space24),
          ],
        ),
      ),
    );
  }

  Widget _backButton(BuildContext context) {
    return RIconButton(
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
    );
  }

  /// Share action (#722) — opens the wrapped recap card preview. Only built on
  /// the non-empty data path (the empty/loading/error states have no card).
  Widget _shareButton(
    BuildContext context,
    EventRecap recap,
    Map<String, String> roster,
    Event event,
  ) {
    return RIconButton(
      key: EventKeys.recapShareButton,
      variant: RIconButtonVariant.ghost,
      icon: Iconsax.export_1,
      tooltip: context.l10n.recapShareButton,
      onTap: () => showRecapShareSheet(
        context,
        recap: recap,
        roster: roster,
        eventType: event.type,
        eventRef: (groupId: groupId, eventId: eventId),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    EventRecap recap,
    Map<String, String> roster,
    String? uid,
    Event event,
  ) {
    // Per-currency blocks span every balance ∪ expense currency, GCC-first.
    final currencies = sortedGccFirst({
      ...recap.participantNetsByCurrency.keys,
      ...recap.totalSpentByCurrency.keys,
    });
    final multi = currencies.length > 1;

    return [
      Text(
        recap.eventName,
        style: AppTypography.sans(
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
        style: AppTypography.sans(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: context.colors.textSecondary,
        ),
      ),
      // #766: a closed event with a captured snapshot serves frozen spending —
      // surface that the spending story is locked (settlement stays live).
      if (event.isClosed && event.spendingSnapshot != null)
        _frozenCaption(context, event.closedAt),
      SizedBox(height: context.spacing.space24),

      _totalCard(context, recap, currencies, multi),

      for (final ccy in currencies) ...[
        SizedBox(height: context.spacing.space24),
        if (multi)
          _currencyHeader(context, ccy, recap.totalSpentByCurrency[ccy]),
        ..._currencyBlock(context, recap, roster, uid, ccy),
      ],

      ..._settleCtaSection(context, recap, currencies),
    ];
  }

  /// Actionable event-vs-group settle CTA (#721 deferred item — last piece of
  /// #202). Shown ONCE (not per-currency) when ANY currency is outstanding,
  /// using the same `isSettledByCurrency[ccy] ?? true` test each per-currency
  /// status card uses (so CTA + status cards can never disagree). Navigation +
  /// display only — reads the already-computed map, persists nothing. Both
  /// routes already exist; pushed with absolute path strings (the established
  /// convention), back returns to the recap. Settlements stay live after close
  /// (#723/#766), so the CTA shows regardless of `event.isClosed`.
  List<Widget> _settleCtaSection(
    BuildContext context,
    EventRecap recap,
    List<String> currencies,
  ) {
    final anyOutstanding = currencies.any(
      (ccy) => !(recap.isSettledByCurrency[ccy] ?? true),
    );
    if (!anyOutstanding) return const [];
    final c = context.colors;
    return [
      SizedBox(height: context.spacing.space24),
      Container(
        key: EventKeys.recapSettleCta,
        width: double.infinity,
        padding: EdgeInsetsDirectional.all(context.spacing.space20),
        decoration: BoxDecoration(
          color: c.cardSurface,
          borderRadius: BorderRadius.circular(context.spacing.radiusCard),
          boxShadow: context.shadows.raised,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.recapSettleCtaTitle,
              style: AppTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            SizedBox(height: context.spacing.space4),
            Text(
              context.l10n.recapSettleCtaBody,
              style: AppTypography.sans(fontSize: 13, color: c.textSecondary),
            ),
            SizedBox(height: context.spacing.space16),
            FilledButton(
              key: EventKeys.recapSettleEventButton,
              onPressed: () {
                HapticService.lightClick();
                GoRouter.of(
                  context,
                ).push('/group/$groupId/event/$eventId/ledger/settle-up');
              },
              child: Text(context.l10n.recapSettleThisEvent),
            ),
            SizedBox(height: context.spacing.space8),
            OutlinedButton(
              key: EventKeys.recapSettleGroupButton,
              onPressed: () {
                HapticService.lightClick();
                GoRouter.of(context).push('/group/$groupId/settle-up');
              },
              child: Text(context.l10n.recapSettleAtGroup),
            ),
          ],
        ),
      ),
    ];
  }

  // ── Total + your-position card ──────────────────────────────────────────

  Widget _totalCard(
    BuildContext context,
    EventRecap recap,
    List<String> currencies,
    bool multi,
  ) {
    final c = context.colors;
    final children = <Widget>[
      _sectionLabel(context, context.l10n.recapTotalSpent),
    ];

    if (!multi) {
      // Single currency: one hero total + the user's folded net/paid/share.
      final ccy = currencies.isEmpty ? 'OMR' : currencies.first;
      children.add(
        RAmount(
          value: recap.totalSpentByCurrency[ccy] ?? Decimal.zero,
          currency: ccy,
          size: 30,
          weight: FontWeight.w700,
        ),
      );
      final net = recap.userNetByCurrency[ccy];
      if (net != null) {
        children.addAll([
          Divider(height: context.spacing.space24, color: c.rule),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.recapNet,
                  style: AppTypography.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
              ),
              RAmount(value: net, currency: ccy, sign: true, size: 20),
            ],
          ),
          SizedBox(height: context.spacing.space8),
          _miniStat(
            context,
            context.l10n.recapYouPaid,
            recap.userPaidByCurrency[ccy] ?? Decimal.zero,
            ccy,
          ),
          _miniStat(
            context,
            context.l10n.recapYourShare,
            recap.userShareByCurrency[ccy] ?? Decimal.zero,
            ccy,
          ),
        ]);
      }
    } else {
      // Multi currency: one row per currency, never cross-summed, + the note.
      for (final ccy in currencies) {
        if (!recap.totalSpentByCurrency.containsKey(ccy)) continue;
        children.add(
          Padding(
            padding: EdgeInsetsDirectional.only(top: context.spacing.space8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    ccy,
                    style: AppTypography.sans(fontSize: 14, color: c.textSecondary),
                  ),
                ),
                RAmount(
                  value: recap.totalSpentByCurrency[ccy]!,
                  currency: ccy,
                  showCurrency: false,
                  size: 18,
                  weight: FontWeight.w700,
                ),
              ],
            ),
          ),
        );
      }
      children.addAll([
        SizedBox(height: context.spacing.space12),
        Text(
          context.l10n.recapMultiCurrencyNote,
          style: AppTypography.sans(fontSize: 12, color: c.textSecondary),
        ),
      ]);
    }

    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
      padding: EdgeInsetsDirectional.all(context.spacing.space20),
    );
  }

  Widget _miniStat(
    BuildContext context,
    String label,
    Decimal value,
    String ccy,
  ) {
    return Padding(
      padding: EdgeInsetsDirectional.only(top: context.spacing.space4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.sans(
                fontSize: 13,
                color: context.colors.textSecondary,
              ),
            ),
          ),
          RAmount(value: value, currency: ccy, size: 13),
        ],
      ),
    );
  }

  // ── Per-currency block ──────────────────────────────────────────────────

  Widget _currencyHeader(BuildContext context, String ccy, Decimal? total) {
    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: context.spacing.space8),
      child: Row(
        children: [
          Text(
            ccy,
            style: AppTypography.sans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: context.colors.primary,
            ),
          ),
          if (total != null) ...[
            Text(
              '  ·  ',
              style: AppTypography.sans(
                fontSize: 13,
                color: context.colors.textSecondary,
              ),
            ),
            RAmount(value: total, currency: ccy, showCurrency: false, size: 13),
          ],
        ],
      ),
    );
  }

  List<Widget> _currencyBlock(
    BuildContext context,
    EventRecap recap,
    Map<String, String> roster,
    String? uid,
    String ccy,
  ) {
    final payers =
        recap.payerTotalsByCurrency[ccy] ?? const <RecapPersonAmount>[];
    final biggest = recap.biggestExpenseByCurrency[ccy];
    final cats =
        recap.categoryTotalsByCurrency[ccy] ?? const <RecapCategoryTotal>[];
    final nets = recap.participantNetsByCurrency[ccy] ?? const <RecapNet>[];
    final settled = recap.isSettledByCurrency[ccy] ?? true;

    final gap = SizedBox(height: context.spacing.space16);
    final widgets = <Widget>[];

    // Highlights — each card only when its data is present (never .first on []).
    if (payers.isNotEmpty || biggest != null) {
      widgets.add(_highlightsRow(context, payers, biggest, roster, ccy));
      widgets.add(gap);
    }
    if (cats.isNotEmpty) {
      widgets.add(_sectionLabel(context, context.l10n.recapByCategory));
      widgets.add(_categoryCard(context, cats, ccy));
      widgets.add(gap);
    }
    if (payers.isNotEmpty) {
      widgets.add(_sectionLabel(context, context.l10n.recapWhoPaid));
      widgets.add(_payerCard(context, payers, roster, uid, ccy));
      widgets.add(gap);
    }
    if (nets.isNotEmpty) {
      widgets.add(_sectionLabel(context, context.l10n.recapWhoUpDown));
      widgets.add(_netsCard(context, nets, roster, uid, ccy));
      widgets.add(gap);
    }
    widgets.add(_statusCard(context, settled, nets));
    return widgets;
  }

  Widget _highlightsRow(
    BuildContext context,
    List<RecapPersonAmount> payers,
    RecapExpenseRef? biggest,
    Map<String, String> roster,
    String ccy,
  ) {
    final cards = <Widget>[];
    if (payers.isNotEmpty) {
      final top = payers.first;
      final name = roster[top.participantId] ?? context.l10n.ledgerSomeone;
      cards.add(
        Expanded(
          child: _highlightCard(
            context,
            label: context.l10n.recapTopPayer,
            body: Row(
              children: [
                RAvatar(name: name, size: 22),
                SizedBox(width: context.spacing.space8),
                Flexible(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            amount: top.amount,
            ccy: ccy,
          ),
        ),
      );
    }
    if (biggest != null) {
      final desc = biggest.description?.trim();
      final label = (desc != null && desc.isNotEmpty)
          ? desc
          : categoryNameForId(biggest.categoryId, context.l10n);
      cards.add(
        Expanded(
          child: _highlightCard(
            context,
            label: context.l10n.recapBiggestExpense,
            body: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
            amount: biggest.amount,
            ccy: ccy,
          ),
        ),
      );
    }
    // IntrinsicHeight bounds the Row's height so stretch equalizes both cards
    // (a bare stretch in the vertically-unbounded scroll view → infinite height).
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) SizedBox(width: context.spacing.space8),
            cards[i],
          ],
        ],
      ),
    );
  }

  Widget _highlightCard(
    BuildContext context, {
    required String label,
    required Widget body,
    required Decimal amount,
    required String ccy,
  }) {
    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _microLabel(context, label),
          SizedBox(height: context.spacing.space8),
          body,
          SizedBox(height: context.spacing.space8),
          RAmount(value: amount, currency: ccy, size: 13),
        ],
      ),
      padding: EdgeInsetsDirectional.all(context.spacing.space12),
    );
  }

  Widget _categoryCard(
    BuildContext context,
    List<RecapCategoryTotal> cats,
    String ccy,
  ) {
    final maxTotal = cats.first.total; // desc-sorted
    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < cats.length; i++) ...[
            if (i > 0) SizedBox(height: context.spacing.space12),
            Row(
              children: [
                _dot(
                  context,
                  categoryColorForId(context.colors, cats[i].categoryId),
                ),
                SizedBox(width: context.spacing.space8),
                Expanded(
                  child: Text(
                    categoryNameForId(cats[i].categoryId, context.l10n),
                    style: AppTypography.sans(
                      fontSize: 13,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
                RAmount(value: cats[i].total, currency: ccy, size: 13),
              ],
            ),
            SizedBox(height: context.spacing.space8),
            _bar(
              context,
              ratio: maxTotal > Decimal.zero
                  ? cats[i].total.toDouble() / maxTotal.toDouble()
                  : 0,
              color: categoryColorForId(context.colors, cats[i].categoryId),
            ),
          ],
        ],
      ),
    );
  }

  Widget _payerCard(
    BuildContext context,
    List<RecapPersonAmount> payers,
    Map<String, String> roster,
    String? uid,
    String ccy,
  ) {
    final maxPaid = payers.first.amount; // desc-sorted
    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < payers.length; i++) ...[
            if (i > 0) SizedBox(height: context.spacing.space12),
            Row(
              children: [
                RAvatar(name: roster[payers[i].participantId] ?? '?', size: 22),
                SizedBox(width: context.spacing.space8),
                Expanded(
                  child: _personName(
                    context,
                    payers[i].participantId,
                    roster,
                    uid,
                  ),
                ),
                RAmount(value: payers[i].amount, currency: ccy, size: 13),
              ],
            ),
            SizedBox(height: context.spacing.space8),
            _bar(
              context,
              ratio: maxPaid > Decimal.zero
                  ? payers[i].amount.toDouble() / maxPaid.toDouble()
                  : 0,
              color: context.colors.ink2,
            ),
          ],
        ],
      ),
    );
  }

  Widget _netsCard(
    BuildContext context,
    List<RecapNet> nets,
    Map<String, String> roster,
    String? uid,
    String ccy,
  ) {
    return _card(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < nets.length; i++)
            _netRow(context, nets[i], roster, uid, ccy),
        ],
      ),
      padding: EdgeInsetsDirectional.zero,
    );
  }

  Widget _netRow(
    BuildContext context,
    RecapNet n,
    Map<String, String> roster,
    String? uid,
    String ccy,
  ) {
    final isYou = uid != null && n.participantId == uid;
    final name = roster[n.participantId] ?? context.l10n.ledgerSomeone;
    final isZero = n.net == Decimal.zero;
    return Container(
      color: isYou ? context.colors.cardSoft : null,
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: context.spacing.space16,
        vertical: context.spacing.space12,
      ),
      child: Row(
        children: [
          RAvatar(name: name, size: 28),
          SizedBox(width: context.spacing.space12),
          Expanded(child: _personName(context, n.participantId, roster, uid)),
          if (isZero)
            Text(
              context.l10n.recapSettledRow,
              style: AppTypography.sans(
                fontSize: 13,
                color: context.colors.textSecondary,
              ),
            )
          else
            RAmount(value: n.net, currency: ccy, sign: true, size: 13),
        ],
      ),
    );
  }

  Widget _personName(
    BuildContext context,
    String id,
    Map<String, String> roster,
    String? uid,
  ) {
    final name = roster[id] ?? context.l10n.ledgerSomeone;
    final isYou = uid != null && id == uid;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: name),
          if (isYou)
            TextSpan(
              text: ' · ${context.l10n.recapYouSuffix}',
              style: TextStyle(
                fontWeight: FontWeight.w400,
                color: context.colors.textSecondary,
              ),
            ),
        ],
      ),
      overflow: TextOverflow.ellipsis,
      style: AppTypography.sans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: context.colors.textPrimary,
      ),
    );
  }

  Widget _statusCard(BuildContext context, bool settled, List<RecapNet> nets) {
    final c = context.colors;
    if (settled) {
      return _statusBox(
        context,
        background: c.cardSoft,
        accent: c.successText,
        icon: Iconsax.tick_circle,
        title: context.l10n.recapSettledTitle,
        subtitle: context.l10n.recapSettledSubtitle,
      );
    }
    final debtors = nets.where((n) => n.net < Decimal.zero).length;
    return _statusBox(
      context,
      background: c.saffronTint,
      accent: c.warning,
      icon: Iconsax.warning_2,
      title: context.l10n.recapOutstandingTitle,
      subtitle: context.l10n.recapOutstandingSubtitle(debtors),
    );
  }

  Widget _statusBox(
    BuildContext context, {
    required Color background,
    required Color accent,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsetsDirectional.all(context.spacing.space16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(context.spacing.radiusCard),
        border: Border.all(color: accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              SizedBox(width: context.spacing.space8),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: context.spacing.space8),
          Text(
            subtitle,
            style: AppTypography.sans(fontSize: 13, color: context.colors.textSecondary),
          ),
        ],
      ),
    );
  }

  // ── Small shared bits ───────────────────────────────────────────────────

  Widget _card(
    BuildContext context,
    Widget child, {
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: padding ?? EdgeInsetsDirectional.all(context.spacing.space16),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(context.spacing.radiusCard),
        boxShadow: context.shadows.raised,
      ),
      child: child,
    );
  }

  Widget _dot(BuildContext context, Color color) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _bar(
    BuildContext context, {
    required double ratio,
    required Color color,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 6,
        color: context.colors.rule2,
        child: FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: ratio.clamp(0.0, 1.0),
          child: Container(color: color),
        ),
      ),
    );
  }

  // #766: the closed-event "spending frozen" caption. [closedAt] is nullable —
  // the server timestamp is unresolved during the offline-close window while
  // isClosed + the snapshot are already readable — so the date is conditional
  // (never closedAt!). Mirrors the hub _ClosedBanner's lock + textSecondary.
  Widget _frozenCaption(BuildContext context, DateTime? closedAt) {
    final text = closedAt != null
        ? context.l10n.recapSpendingFrozen(
            formatShortMonthDayYear(context, closedAt),
          )
        : context.l10n.recapSpendingFrozenNoDate;
    return Padding(
      key: EventKeys.recapFrozenCaption,
      padding: EdgeInsetsDirectional.only(top: context.spacing.space8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Iconsax.lock, size: 13, color: context.colors.textSecondary),
          SizedBox(width: context.spacing.space4),
          Flexible(
            child: Text(
              text,
              style: AppTypography.sans(
                fontSize: 12,
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: context.spacing.space8),
      child: Text(
        label,
        style: AppTypography.sans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: context.colors.textSecondary,
        ),
      ),
    );
  }

  // Small highlight-card label (sentence case so it stays l10n-faithful and
  // case-neutral for scripts like Arabic that have no upper/lower distinction).
  Widget _microLabel(BuildContext context, String label) {
    return Text(
      label,
      style: AppTypography.sans(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: context.colors.textSecondary,
      ),
    );
  }

  /// Layout-matched loading placeholder (DESIGN.md §10) approximating the
  /// loaded recap's shape: title + subtitle bars, the hero total card, then
  /// stacked highlight/category/payer/status card blocks. Used for both the
  /// event-detail load and the expenses/settlements/members gate above.
  Widget _loadingSkeleton(BuildContext context) {
    return _wrap(context, [
      SkeletonLoader(
        itemCount: 1,
        itemBuilder: (context, index) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBar(width: 160, height: 24),
            SizedBox(height: context.spacing.space8),
            const SkeletonBar(width: 120, height: 14),
            SizedBox(height: context.spacing.space24),
            const SkeletonCard(height: 140),
            SizedBox(height: context.spacing.space24),
            const SkeletonCard(height: 96),
            SizedBox(height: context.spacing.space16),
            const SkeletonCard(height: 120),
            SizedBox(height: context.spacing.space16),
            const SkeletonCard(height: 72),
          ],
        ),
      ),
    ]);
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

  /// #1030: a source stream hard-errored — the recap's nets would be computed
  /// without its folds. Retry invalidates all three streams (a members- or
  /// settlements-triggered error could never heal off an expenses-only
  /// invalidate).
  Widget _dataUnavailable(BuildContext context, WidgetRef ref, EventRef eventRef) {
    return _wrap(context, [
      const SizedBox(height: 24),
      EmptyStateView(
        icon: Iconsax.warning_2,
        title: context.l10n.recapDataUnavailable,
        message: context.l10n.recapEmptyMessage,
        actionLabel: context.l10n.commonRetry,
        onAction: () {
          ref.invalidate(eventExpensesProvider(eventRef));
          ref.invalidate(eventSettlementsProvider(eventRef));
          ref.invalidate(groupMembersProvider(groupId));
        },
      ),
    ]);
  }
}
