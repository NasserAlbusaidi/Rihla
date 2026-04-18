import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/utils/formatters.dart';
import '../models/group_activity_log_model.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// A single activity log entry tile (D-09).
///
/// Card-style rich tile with initials circle, actor name, description,
/// relative timestamp, and semantic type icon.
///
/// Two display modes:
/// - [compact] = false (default): full card with cardSurface background,
///   shadow, and margin. Used in GroupActivityScreen timeline.
/// - [compact] = true: bare Row content without card container.
///   Used in GroupDetailScreen activity preview section.
///
/// Activity type icon mapping per UI-SPEC:
/// - group_settlement: [Iconsax.money_recive] (primary teal)
/// - event_created: [Iconsax.calendar_add] (textMuted)
/// - event_deleted: [Iconsax.calendar_remove] (textMuted)
/// - member_joined: [Iconsax.profile_add] (textMuted)
/// - member_left: [Iconsax.profile_delete] (textMuted)
class GroupActivityTile extends StatelessWidget {
  final GroupActivityLog activity;

  /// When true, renders only the Row content without card container.
  /// Use inside existing card containers (e.g. GroupDetailScreen preview).
  final bool compact;

  const GroupActivityTile({
    super.key,
    required this.activity,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color, semanticsLabel) = _iconColorAndLabel(context, activity.type);

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Initials circle avatar (48dp)
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: context.colors.inputFill,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              activity.actorName.isNotEmpty
                  ? activity.actorName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Actor name, description, timestamp
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                activity.actorName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                activity.description,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppFormatters.formatRelativeDate(activity.timestamp),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),

        // Type icon with semantics
        Semantics(
          label: semanticsLabel,
          child: Icon(icon, size: 20, color: color),
        ),
      ],
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: content,
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.shadows.raised,
      ),
      child: content,
    );
  }

  /// Returns (icon, color, semanticsLabel) for the given activity type.
  (IconData, Color, String) _iconColorAndLabel(
    BuildContext context,
    String type,
  ) {
    // textMuted-decorative-justified: activity-type glyph tint in leading
    // icon cell; semantic meaning is carried by the text + semanticsLabel,
    // icon is a decorative adjunct that should recede visually.
    final mutedTint = context.colors.textMuted;
    return switch (type) {
      'group_settlement' => (
          Iconsax.money_recive,
          context.colors.primary,
          'Payment recorded',
        ),
      'event_created' => (
          Iconsax.calendar_add,
          mutedTint,
          'Event created',
        ),
      'event_deleted' => (
          Iconsax.calendar_remove,
          mutedTint,
          'Event removed',
        ),
      'member_joined' => (
          Iconsax.profile_add,
          mutedTint,
          'Member joined',
        ),
      'member_left' => (
          Iconsax.profile_delete,
          mutedTint,
          'Member left',
        ),
      _ => (
          Iconsax.info_circle,
          mutedTint,
          'Activity',
        ),
    };
  }
}
