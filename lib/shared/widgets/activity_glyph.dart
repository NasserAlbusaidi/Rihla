import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/theme/tokens/domain_aliases.dart';

/// Category glyph shown in the 36×36 icon tile leading an activity row.
///
/// Verbatim mapping lifted from the `_CategoryIcon` switch in
/// `group_activity_screen.dart` — the richest of the three per-screen variants.
enum ActivityGlyph {
  expenseAdded,
  expenseEdited,
  expenseDeleted,
  settlement,
  eventCreated,
  eventDeleted,
  memberJoined,
  memberLeft,
  groupCreated,
  generic,
}

/// 36×36 tinted icon tile for an [ActivityGlyph].
class ActivityCategoryIcon extends StatelessWidget {
  const ActivityCategoryIcon({super.key, required this.glyph});

  final ActivityGlyph glyph;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sageSoft = Color.alphaBlend(
      colors.success.withValues(alpha: 0.18),
      colors.cardSurface,
    );
    final (bg, fg, icon, hasBorder) = switch (glyph) {
      // Money/wallet glyph (matches the settle-up total chip, #157) — not a
      // bare chevron, which read as navigation amid the other category
      // glyphs (#160).
      ActivityGlyph.settlement => (
        sageSoft,
        colors.success,
        Iconsax.wallet_3,
        false,
      ),
      ActivityGlyph.eventCreated => (
        colors.saffronSoft,
        colors.primaryDark,
        Iconsax.calendar_1,
        true,
      ),
      ActivityGlyph.eventDeleted => (
        colors.cardSoft,
        colors.textSecondary,
        Iconsax.calendar_remove,
        true,
      ),
      ActivityGlyph.memberJoined => (
        colors.cardSoft,
        colors.cat2,
        Iconsax.user_add,
        true,
      ),
      ActivityGlyph.memberLeft => (
        colors.cardSoft,
        colors.textSecondary,
        Iconsax.user_minus,
        true,
      ),
      // Genesis marker (#1018) — a flag reads as "the journey started" (matches
      // the Rihla trip framing) and is visually distinct from eventCreated
      // (calendar) / memberJoined (user), which are about the group's CONTENTS,
      // not the group itself. Shares the "created"-family palette with
      // eventCreated/expenseAdded so creation actions read as one visual set.
      ActivityGlyph.groupCreated => (
        colors.saffronSoft,
        colors.primaryDark,
        Iconsax.flag,
        true,
      ),
      // Receipt family — a money glyph, not a navigation chevron; parallels
      // the settlement wallet glyph (#160).
      ActivityGlyph.expenseAdded => (
        colors.saffronSoft,
        colors.primaryDark,
        Iconsax.receipt_add,
        true,
      ),
      ActivityGlyph.expenseEdited => (
        colors.cardSoft,
        colors.textSecondary,
        Iconsax.receipt_edit,
        true,
      ),
      ActivityGlyph.expenseDeleted => (
        colors.cardSoft,
        colors.textSecondary,
        Iconsax.receipt_minus,
        true,
      ),
      ActivityGlyph.generic => (
        colors.cardSoft,
        colors.textSecondary,
        Iconsax.activity,
        true,
      ),
    };
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(context.spacing.radiusSmall),
        border: hasBorder ? Border.all(color: colors.rule, width: 0.5) : null,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: fg),
    );
  }
}
