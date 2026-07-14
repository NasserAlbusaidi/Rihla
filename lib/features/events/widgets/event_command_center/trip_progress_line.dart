import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/directional_icon.dart';
import '../../keys/event_keys.dart';

/// #811: open-event progress line that keeps the recap labelled and tappable.
/// The outer key can also mark a day-only line; the InkWell key is the recap
/// affordance proof.
class TripProgressLine extends StatelessWidget {
  const TripProgressLine({
    super.key,
    required this.dayLabel,
    required this.showRecap,
    required this.onViewRecap,
  });

  final String? dayLabel;
  final bool showRecap;
  final VoidCallback onViewRecap;

  @override
  Widget build(BuildContext context) {
    if (dayLabel == null && !showRecap) return const SizedBox.shrink();

    final colors = context.colors;
    final text = [
      ?dayLabel,
      if (showRecap) context.l10n.eventViewReceipt,
    ].join(' · ');
    final row = Row(
      children: [
        if (showRecap) ...[
          Icon(Iconsax.cup, size: 14, color: colors.textSecondary),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ),
        if (showRecap) ...[
          const SizedBox(width: 4),
          DirectionalIcon(Iconsax.arrow_right, size: 14, color: colors.primary),
        ],
      ],
    );

    if (!showRecap) {
      return Align(
        key: EventKeys.openRecapBanner,
        alignment: AlignmentDirectional.centerStart,
        child: row,
      );
    }

    return Align(
      key: EventKeys.openRecapBanner,
      alignment: AlignmentDirectional.centerStart,
      child: InkWell(
        key: EventKeys.openRecapBannerViewRecap,
        onTap: onViewRecap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(alignment: AlignmentDirectional.centerStart, child: row),
        ),
      ),
    );
  }
}
