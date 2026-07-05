import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/supported_currencies.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/localized_dates.dart';
import '../../../shared/widgets/cover_art.dart';
import '../../../shared/widgets/falaj_fork.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../ledger/utils/ledger_categories.dart';
import '../models/event_model.dart';
import '../models/event_recap.dart';

/// The shareable "wrapped" recap poster (#722 Slice 4 of #202). A FIXED-width
/// ([kWidth]) brand artifact rendered into a [RepaintBoundary] and exported as a
/// 1080×1350 PNG. Pure display over [EventRecap] — no money math, no writes;
/// every amount is INBOUND from already-correct `BalanceCalculator` output.
///
/// Always laid out in the LIGHT palette (the preview sheet wraps it in
/// `AppTheme.lightTheme`) so the shared image looks identical regardless of the
/// viewer's app theme. Per-currency: a single hero block (the GCC-first spend
/// currency) + a note listing other currencies — Decimals are never cross-summed.
class RecapShareCard extends StatelessWidget {
  const RecapShareCard({
    super.key,
    required this.recap,
    required this.roster,
    required this.eventType,
  });

  /// Per-currency money projection of the event. Assumed non-empty (the share
  /// affordance is hidden when `recap.isEmpty`).
  final EventRecap recap;

  /// participantId → display name, resolved by the caller (the model holds ids).
  final Map<String, String> roster;

  /// Drives the procedural [CoverArt] band palette.
  final EventType eventType;

  /// Logical width of the poster. At capture `pixelRatio` 3 → a 1080px image.
  static const double kWidth = 360;
  static const double _coverHeight = 150;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hero = _heroCurrency();
    final heroTotal = recap.totalSpentByCurrency[hero] ?? Decimal.zero;

    return SizedBox(
      width: kWidth,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.scaffoldBackground,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cover(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heroBlock(context, hero, heroTotal),
                  const SizedBox(height: 16),
                  _statsRow(context, hero, heroTotal),
                  const SizedBox(height: 14),
                  Divider(height: 1, color: c.rule),
                  const SizedBox(height: 14),
                  _highlightsRow(context, hero),
                  ..._categoriesSection(context, hero, heroTotal),
                  const SizedBox(height: 16),
                  _footer(context, hero),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Hero currency = GCC-first spend currency (matches the recap screen). ──
  String _heroCurrency() {
    final spend = sortedGccFirst(recap.totalSpentByCurrency.keys);
    if (spend.isNotEmpty) return spend.first;
    final nets = sortedGccFirst(recap.participantNetsByCurrency.keys);
    return nets.isEmpty ? 'OMR' : nets.first;
  }

  // ── Cover band: procedural art + caption + serif title + date range. ──────
  Widget _cover(BuildContext context) {
    final c = context.colors;
    final start = recap.startDate;
    final end = recap.endDate;
    final monthDate = start ?? end;
    final caption = monthDate != null
        ? context.l10n.recapCardCaption(formatMonthYear(context, monthDate))
        : context.l10n.recapCardCaptionPlain;
    final range = formatDateRangeShort(context, start, end);

    return SizedBox(
      height: _coverHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverArt.forEventType(eventType),
          // Ink scrim so the overlay text stays legible over any palette.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  c.headerGradientStart.withValues(alpha: 0),
                  c.headerGradientStart.withValues(alpha: 0.38),
                ],
                stops: const [0.45, 1.0],
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.bottomStart,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(
                      context,
                      fontSize: 9,
                      color: c.textOnPrimary.withValues(alpha: 0.92),
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    recap.eventName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.displayOf(
                      context,
                      fontSize: 27,
                      color: c.textOnPrimary,
                      height: 1.05,
                    ),
                  ),
                  if (range.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      range,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.mono(
                        fontSize: 9.5,
                        color: c.textOnPrimary.withValues(alpha: 0.85),
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero total + multi-currency note. ────────────────────────────────────
  Widget _heroBlock(BuildContext context, String hero, Decimal heroTotal) {
    final others = sortedGccFirst(recap.totalSpentByCurrency.keys)
        .where((x) => x != hero)
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _microLabel(context, context.l10n.recapTotalSpent),
        const SizedBox(height: 2),
        RAmount(value: heroTotal, currency: hero, size: 50, weight: FontWeight.w600),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 5),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('+ ',
                  style: TextStyle(fontSize: 12, color: context.colors.textSecondary)),
              for (var i = 0; i < others.length; i++) ...[
                if (i > 0)
                  Text(' · ',
                      style: TextStyle(
                          fontSize: 12, color: context.colors.textSecondary)),
                RAmount(
                  value: recap.totalSpentByCurrency[others[i]]!,
                  currency: others[i],
                  size: 12,
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  // ── 3 stats: People · Expenses · Avg/day (or Per person when undated). ────
  Widget _statsRow(BuildContext context, String hero, Decimal heroTotal) {
    final third = _thirdStat(context, hero, heroTotal);
    // IntrinsicHeight bounds the Row so stretch can equalize the three cards
    // (a bare stretch in the vertically-unbounded card column → infinite height).
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _statCard(context, context.l10n.recapCardPeople,
                big: '${recap.participantCount}'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statCard(context, context.l10n.recapCardExpenses,
                big: '${recap.expenseCount}'),
          ),
          const SizedBox(width: 8),
          Expanded(child: third),
        ],
      ),
    );
  }

  /// Avg/day when both dates exist (over inclusive days), else per-person. Both
  /// are DISPLAY-ONLY ratios of the hero-currency total — never persisted, never
  /// summed. Decimal division rounded to the currency's precision for render.
  Widget _thirdStat(BuildContext context, String hero, Decimal heroTotal) {
    final decimals = AppFormatters.currencyConfig[hero]?.decimals ?? 2;
    final start = recap.startDate;
    final end = recap.endDate;
    if (start != null && end != null) {
      // Normalize to date-only before differencing (matches the defensive
      // pattern in event_command_center) so a stray time component on a
      // migrated/Admin/TZ-shifted date can't drift the inclusive day count.
      final days = DateUtils.dateOnly(end)
              .difference(DateUtils.dateOnly(start))
              .inDays +
          1;
      final safeDays = days < 1 ? 1 : days;
      final avg = (heroTotal / Decimal.fromInt(safeDays))
          .toDecimal(scaleOnInfinitePrecision: decimals);
      return _statCard(context, context.l10n.recapCardAvgPerDay,
          amount: avg, currency: hero);
    }
    final heads = recap.participantCount < 1 ? 1 : recap.participantCount;
    final perPerson = (heroTotal / Decimal.fromInt(heads))
        .toDecimal(scaleOnInfinitePrecision: decimals);
    return _statCard(context, context.l10n.recapCardPerPerson,
        amount: perPerson, currency: hero);
  }

  Widget _statCard(BuildContext context, String label,
      {String? big, Decimal? amount, String? currency}) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: c.cardSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.rule),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _microLabel(context, label, size: 8),
          const SizedBox(height: 4),
          if (big != null)
            Text(big,
                style: AppTypography.display(fontSize: 21, color: c.textPrimary))
          else if (amount != null)
            RAmount(value: amount, currency: currency ?? 'OMR', size: 13),
        ],
      ),
    );
  }

  // ── Top spender + biggest splurge. ───────────────────────────────────────
  Widget _highlightsRow(BuildContext context, String hero) {
    final c = context.colors;
    final payers =
        recap.payerTotalsByCurrency[hero] ?? const <RecapPersonAmount>[];
    final top = payers.isEmpty ? null : payers.first;
    final biggest = recap.biggestExpenseByCurrency[hero];

    final children = <Widget>[];
    if (top != null) {
      // Bare name — NO "· you" affordance: this is an artifact shared to the
      // whole group, so personalizing one viewer's copy reads wrong to everyone
      // else (matches the signed-off mockup).
      final name = roster[top.participantId] ?? context.l10n.ledgerSomeone;
      children.add(Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _microLabel(context, context.l10n.recapCardTopSpender, size: 9),
            const SizedBox(height: 5),
            Row(children: [
              RAvatar(name: name, size: 20),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary),
                ),
              ),
            ]),
            const SizedBox(height: 2),
            RAmount(value: top.amount, currency: hero, size: 12),
          ],
        ),
      ));
    }
    if (biggest != null) {
      final desc = biggest.description?.trim();
      final label = (desc != null && desc.isNotEmpty)
          ? desc
          : categoryNameForId(biggest.categoryId, context.l10n);
      children.add(Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _microLabel(context, context.l10n.recapCardBiggest, size: 9),
            const SizedBox(height: 5),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary)),
            const SizedBox(height: 2),
            RAmount(value: biggest.amount, currency: hero, size: 12),
          ],
        ),
      ));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            children[i],
          ],
        ],
      ),
    );
  }

  // ── "Where it went" segmented bar + legend (top 3 + folded Other). ───────
  List<Widget> _categoriesSection(
      BuildContext context, String hero, Decimal heroTotal) {
    final cats =
        recap.categoryTotalsByCurrency[hero] ?? const <RecapCategoryTotal>[];
    if (cats.isEmpty || heroTotal <= Decimal.zero) return const [];

    // Top-3 NAMED categories shown; everything else — the 4th+ AND any 'other'
    // bucket — folds into ONE "Other" segment. (Excluding 'other' from the top-3
    // is what prevents a duplicate "Other" chip when it ranks in the top three.)
    final shown = cats.where((c) => c.categoryId != 'other').take(3).toList();
    final shownIds = shown.map((c) => c.categoryId).toSet();
    final restTotal = cats
        .where((c) => !shownIds.contains(c.categoryId))
        .fold(Decimal.zero, (Decimal s, RecapCategoryTotal e) => s + e.total);

    final segments = <_Seg>[
      for (final cat in shown)
        _Seg(
          ratio: (cat.total / heroTotal).toDouble(),
          color: categoryColorForId(context.colors, cat.categoryId),
          label: categoryNameForId(cat.categoryId, context.l10n),
        ),
      if (restTotal > Decimal.zero)
        _Seg(
          ratio: (restTotal / heroTotal).toDouble(),
          color: categoryColorForId(context.colors, 'other'),
          label: categoryNameForId('other', context.l10n),
        ),
    ];

    return [
      const SizedBox(height: 14),
      _microLabel(context, context.l10n.recapCardWhereItWent, size: 9),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 11,
          child: Row(
            // stretch → each segment gets a TIGHT 11px height; a childless
            // ColoredBox under the default (center) cross-axis would collapse to
            // height 0 (RenderProxyBox sizes to constraints.smallest) — the bar
            // would render invisible.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < segments.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  flex: (segments[i].ratio.clamp(0.02, 1.0) * 1000).round(),
                  child: ColoredBox(color: segments[i].color),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 7),
      Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          for (final seg in segments) _legendChip(context, seg),
        ],
      ),
    ];
  }

  Widget _legendChip(BuildContext context, _Seg seg) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: seg.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(seg.label,
            style: TextStyle(fontSize: 10, color: context.colors.textSecondary)),
      ],
    );
  }

  // ── Footer: settlement status pill + Rihla wordmark + close ritual. ──────
  Widget _footer(BuildContext context, String hero) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: c.rule),
        const SizedBox(height: 12),
        Row(
          children: [
            // Expanded + start-Align keeps the pill compact-left while letting
            // its internal text ellipsize before it can overrun the brand (a
            // long locale string — e.g. Arabic "still to settle" — must not push
            // past the 360 edge).
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _statusPill(context, hero),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Rihla',
                    style: AppTypography.display(
                        fontSize: 17, color: c.textPrimary)),
                const SizedBox(height: 2),
                FalajFork(size: const Size(30, 6), color: c.primary),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            context.l10n.recapRecordedInRihla,
            style: AppTypography.caption(
              context,
              fontSize: 8,
              color: c.textSecondary,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusPill(BuildContext context, String hero) {
    final c = context.colors;
    final settled = recap.isSettledByCurrency[hero] ?? true;
    final nets = recap.participantNetsByCurrency[hero] ?? const <RecapNet>[];
    final debtors = nets.where((n) => n.net < Decimal.zero).length;
    final label = settled
        ? context.l10n.recapCardAllSettled
        : context.l10n.recapCardStillToSettle(debtors);
    final accent = settled ? c.successText : c.primaryDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.saffronTint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(settled ? Icons.check_circle_outline : Icons.error_outline,
              size: 12, color: accent),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: accent)),
          ),
        ],
      ),
    );
  }

  Widget _microLabel(BuildContext context, String label, {double size = 9}) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.caption(
        context,
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: context.colors.textSecondary,
        letterSpacing: 1,
      ),
    );
  }
}

/// One segment of the "where it went" bar — a ratio of the hero total + label.
class _Seg {
  const _Seg({required this.ratio, required this.color, required this.label});
  final double ratio;
  final Color color;
  final String label;
}
