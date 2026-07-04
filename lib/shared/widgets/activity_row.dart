import 'package:flutter/material.dart';

import '../../core/theme/tokens/domain_aliases.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/utils/localized_dates.dart';
import 'activity_glyph.dart';

/// One row in a day-grouped activity feed — icon tile, actor + description,
/// optional group tag / audit detail, and a trailing amount + relative time.
///
/// Anatomy lifted from the `_ActivityRow` variants shared by the group,
/// event, and cross-group activity screens.
class ActivityRow extends StatelessWidget {
  const ActivityRow({
    super.key,
    required this.glyph,
    required this.actorName,
    required this.description,
    required this.timestamp,
    this.groupName,
    this.trailingAmount,
    this.detail,
    this.divider = false,
    this.maxLines = 2,
    this.muted = false,
    this.onTap,
  });

  final ActivityGlyph glyph;
  final String actorName;
  final String description;
  final DateTime timestamp;

  /// Renders a bordered tag chip below the description when non-null.
  final String? groupName;

  /// Caller-built trailing amount widget (typically an [RAmount]).
  final Widget? trailingAmount;

  /// Audit-chip widget slot rendered below the actor/description line.
  final Widget? detail;
  final bool divider;
  final int maxLines;

  /// When true, dims the actor name and the trailing amount — used for
  /// inert/self-referential rows.
  final bool muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = trailingAmount == null
        ? null
        : (muted
              ? Opacity(opacity: 0.6, child: trailingAmount)
              : trailingAmount!);

    final content = Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
      child: Column(
        children: [
          Row(
            // Top-align so the category icon pins to the first line when a
            // long actor + verb phrase wraps to two lines (#159).
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ActivityCategoryIcon(glyph: glyph),
              SizedBox(width: context.spacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: actorName,
                            style: AppTypography.sans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: muted
                                  ? colors.textSecondary
                                  : colors.textPrimary,
                            ),
                          ),
                          const TextSpan(text: ' '),
                          TextSpan(
                            text: description,
                            style: AppTypography.sans(
                              fontSize: 14,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail != null) detail!,
                    if (groupName != null) ...[
                      SizedBox(height: context.spacing.space4),
                      _GroupChip(groupName: groupName!),
                    ],
                  ],
                ),
              ),
              SizedBox(width: context.spacing.space12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (amount != null) ...[amount, const SizedBox(height: 2)],
                  Text(
                    formatRelativeShort(context, timestamp),
                    style: AppTypography.caption(
                      context,
                      fontSize: 10,
                      color: colors.textSecondary,
                      letterSpacing: 0.4,
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
    );

    return onTap == null ? content : InkWell(onTap: onTap, child: content);
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.groupName});

  final String groupName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.cardSoft,
        borderRadius: BorderRadius.circular(context.spacing.radiusPill),
        border: Border.all(color: colors.rule, width: 0.5),
      ),
      child: Text(
        groupName,
        style: AppTypography.sans(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
