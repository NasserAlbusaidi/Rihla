import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/localized_dates.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../activity/utils/activity_display.dart';
import '../../groups/models/group_activity_log_model.dart';

/// One row in the cross-group activity feed.
///
/// Renders: actor avatar (journal-stamp palette via [RAvatar]) · bold actor
/// name + grey verb-phrase description · group tag chip + relative timestamp.
class ActivityRow extends StatelessWidget {
  const ActivityRow({
    super.key,
    required this.activity,
    required this.groupName,
    required this.groupId,
    this.onTap,
  });

  final GroupActivityLog activity;
  final String groupName;
  final String groupId;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final description = localizedGroupActivityText(context.l10n, activity);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          // Top-align so the avatar pins to the first line when a long
          // actor + verb phrase wraps to two lines, rather than floating to
          // the vertical centre against the taller text column (#159).
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RAvatar(name: activity.actorName, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: activity.actorName,
                          style: AppTypography.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.cardSoft,
                          borderRadius: BorderRadius.circular(9999),
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
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatRelativeShort(context, activity.timestamp),
                        style: AppTypography.mono(
                          fontSize: 10,
                          color: colors.textSecondary,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
