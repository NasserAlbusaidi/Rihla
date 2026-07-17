import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../core/utils/localized_dates.dart';
import '../../../../shared/widgets/cover_art.dart';
import '../../../../shared/widgets/r_amount.dart';
import '../../../events/models/event_model.dart';
import '../../../events/utils/event_display.dart';

class EventRow extends StatelessWidget {
  const EventRow({
    super.key,
    required this.event,
    required this.shareLines,
    required this.groupCurrency,
    required this.divider,
    required this.onTap,
  });

  final Event event;
  final List<({String currency, Decimal net})> shareLines;
  final String groupCurrency;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final dateLabel = _formatDates(context, event.startDate, event.endDate);
    // #807: a dateless event (e.g. the #245 auto-seed) used to fall back to
    // the type label here, printing it twice (the 9px mono chip above already
    // shows it) — omit the subtitle line instead.
    final subtitle = dateLabel;
    final hasShare = shareLines.isNotEmpty;
    final allPositive =
        hasShare && shareLines.every((line) => line.net > Decimal.zero);
    final allNegative =
        hasShare && shareLines.every((line) => line.net < Decimal.zero);
    final netCaption = !hasShare
        ? context.l10n.groupNoShare
        : allPositive
        ? context.l10n.groupEventOwedToYou
        : allNegative
        ? context.l10n.groupEventYouOwe
        : context.l10n.groupEventYourBalance;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(spacing.radiusMedium),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: CoverArt.forEventType(event.type),
                  ),
                ),
                SizedBox(width: context.spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _eventTypeLabel(context, event.type),
                        style: AppTypography.caption(
                          context,
                          fontSize: 9,
                          color: colors.textSecondary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        event.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: AppTypography.sans(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: context.spacing.space8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasShare)
                      // L7: ≥2 lines → every line carries its code; a sole
                      // line only when foreign — keeps the single
                      // group-currency render byte-identical to pre-PR-5.
                      for (var i = 0; i < shareLines.length; i++)
                        Padding(
                          padding: EdgeInsetsDirectional.only(
                            top: i == 0 ? 0 : 2,
                          ),
                          child: RAmount(
                            value: shareLines[i].net,
                            currency: shareLines[i].currency,
                            size: 15,
                            sign: true,
                            showCurrency:
                                shareLines.length >= 2 ||
                                shareLines[i].currency != groupCurrency,
                          ),
                        )
                    else
                      Text(
                        '—',
                        style: AppTypography.sans(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      netCaption,
                      style: AppTypography.sans(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (divider) ...[
              SizedBox(height: context.spacing.space12),
              Container(height: 0.5, color: colors.rule),
            ],
          ],
        ),
      ),
    );
  }

  static String? _formatDates(
    BuildContext context,
    DateTime? start,
    DateTime? end,
  ) {
    if (start != null && end != null) {
      return formatDateRangeShort(context, start, end);
    }
    if (start != null) return formatShortMonthDay(context, start);
    if (end != null) {
      return context.l10n.groupEventEnds(formatShortMonthDay(context, end));
    }
    return null;
  }
}

String _eventTypeLabel(BuildContext context, EventType t) =>
    t.localizedShortLabel(context.l10n);
