import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/constants/supported_currencies.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../../shared/widgets/section_header.dart';
import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../ledger/utils/group_spending_summary.dart';
import '../../ledger/utils/ledger_categories.dart';
import '../keys/group_keys.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_spending_summary_provider.dart';

/// Inline, read-only spending insights for one group (#180). Renders one card
/// per currency (GCC-first): total spent, highest-spending event, top payer,
/// top consumer, and spend-by-category. Owns its [SectionHeader] so an empty
/// group hides header and content together (Gate R1 P2) — the host inserts
/// exactly one sliver.
class GroupSpendingSummarySection extends ConsumerWidget {
  const GroupSpendingSummarySection({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(groupSpendingSummaryProvider(groupId));
    if (summary.isEmpty) return const SizedBox.shrink();

    final memberNames =
        ref.watch(groupBalancesProvider(groupId)).valueOrNull?.memberNames ??
        const <String, String>{};
    final events =
        ref.watch(groupEventsProvider(groupId)).valueOrNull ?? const <Event>[];
    final eventNames = {for (final event in events) event.id: event.name};

    final spacing = context.spacing;
    final currencies = sortedGccFirst(summary.totalSpentByCurrency.keys);

    return Column(
      key: GroupKeys.insightsSection,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 22),
        SectionHeader(title: context.l10n.groupInsightsTitle),
        SizedBox(height: spacing.space8),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.space20),
          child: Column(
            children: [
              for (var i = 0; i < currencies.length; i++) ...[
                if (i > 0) SizedBox(height: spacing.space12),
                _CurrencyInsightsCard(
                  currency: currencies[i],
                  summary: summary,
                  memberNames: memberNames,
                  eventNames: eventNames,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CurrencyInsightsCard extends StatelessWidget {
  const _CurrencyInsightsCard({
    required this.currency,
    required this.summary,
    required this.memberNames,
    required this.eventNames,
  });

  final String currency;
  final GroupSpendingSummary summary;
  final Map<String, String> memberNames;
  final Map<String, String> eventNames;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l10n = context.l10n;

    final total = summary.totalSpentByCurrency[currency] ?? Decimal.zero;
    final topEvent = summary.eventTotalsByCurrency[currency]?.firstOrNull;
    final topPayer = summary.topPayerByCurrency[currency];
    final topConsumer = summary.topConsumerByCurrency[currency];
    final categories =
        summary.categoryTotalsByCurrency[currency] ??
        const <GroupCategoryTotal>[];

    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        boxShadow: context.shadows.raised,
      ),
      padding: EdgeInsets.all(spacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  l10n.insightsTotalSpent,
                  style: AppTypography.sans(
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              RAmount(value: total, currency: currency, size: 22),
            ],
          ),
          if (topEvent != null)
            _InsightRow(
              leading: const _IconStamp(icon: Iconsax.map),
              label: l10n.insightsTopEvent,
              name: eventNames[topEvent.eventId] ?? topEvent.eventId,
              amount: topEvent.total,
              currency: currency,
            ),
          if (topPayer != null)
            _InsightRow(
              leading: RAvatar(
                name: memberNames[topPayer.participantId] ??
                    topPayer.participantId,
                size: 30,
              ),
              label: l10n.insightsTopPayer,
              name: memberNames[topPayer.participantId] ??
                  topPayer.participantId,
              amount: topPayer.amount,
              currency: currency,
            ),
          if (topConsumer != null)
            _InsightRow(
              leading: RAvatar(
                name: memberNames[topConsumer.participantId] ??
                    topConsumer.participantId,
                size: 30,
              ),
              label: l10n.insightsTopConsumer,
              name: memberNames[topConsumer.participantId] ??
                  topConsumer.participantId,
              amount: topConsumer.amount,
              currency: currency,
            ),
          if (categories.isNotEmpty) ...[
            SizedBox(height: spacing.space12),
            Divider(height: 1, thickness: 1, color: colors.rule2),
            SizedBox(height: spacing.space12),
            _CategoryBars(categories: categories, currency: currency),
          ],
        ],
      ),
    );
  }
}

class _IconStamp extends StatelessWidget {
  const _IconStamp({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 16, color: colors.primaryDark),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.leading,
    required this.label,
    required this.name,
    required this.amount,
    required this.currency,
  });

  final Widget leading;
  final String label;
  final String name;
  final Decimal amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsetsDirectional.only(top: spacing.space12),
      child: Row(
        children: [
          leading,
          SizedBox(width: spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: AppTypography.caption(
                    context,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.sans(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: spacing.space12),
          RAmount(
            value: amount,
            currency: currency,
            showCurrency: false,
            size: 14,
          ),
        ],
      ),
    );
  }
}

class _CategoryBars extends StatelessWidget {
  const _CategoryBars({required this.categories, required this.currency});

  final List<GroupCategoryTotal> categories;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l10n = context.l10n;
    final max = categories.first.total;

    return Column(
      children: [
        for (var i = 0; i < categories.length; i++)
          Padding(
            padding: EdgeInsetsDirectional.only(
              top: i == 0 ? 0 : spacing.space8,
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: categoryColorForId(colors, categories[i].categoryId),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                SizedBox(width: spacing.space8),
                SizedBox(
                  width: 92,
                  child: Text(
                    categoryNameForId(categories[i].categoryId, l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.sans(
                      fontSize: 13,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(width: spacing.space8),
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: colors.cardSoft,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: max == Decimal.zero
                          ? 0
                          : (categories[i].total / max)
                                .toDouble()
                                .clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: categoryColorForId(
                            colors,
                            categories[i].categoryId,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: spacing.space8),
                RAmount(
                  value: categories[i].total,
                  currency: currency,
                  showCurrency: false,
                  size: 12,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
