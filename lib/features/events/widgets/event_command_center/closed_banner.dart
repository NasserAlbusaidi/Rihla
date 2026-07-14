import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/directional_icon.dart';
import '../../keys/event_keys.dart';

class ClosedBanner extends StatelessWidget {
  const ClosedBanner({super.key, this.closedByName, this.onViewReceipt});

  final String? closedByName;

  /// #708 close-wiring: opens the shareable Trip Receipt — now a switch to
  /// the Recap tab. Null hides the affordance when there is nothing to
  /// export.
  final VoidCallback? onViewReceipt;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = closedByName;
    final text = (name != null && name.isNotEmpty)
        ? context.l10n.eventClosedBannerBy(name)
        : context.l10n.eventClosedBanner;
    return Container(
      key: EventKeys.closedBanner,
      width: double.infinity,
      color: colors.textPrimary.withValues(alpha: 0.04),
      padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 10),
      child: Row(
        children: [
          Icon(Iconsax.lock, size: 14, color: colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTypography.sans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
          if (onViewReceipt != null) ...[
            const SizedBox(width: 8),
            InkWell(
              key: EventKeys.closedBannerViewReceipt,
              onTap: onViewReceipt,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 4, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.eventViewReceipt,
                      style: AppTypography.sans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 3),
                    DirectionalIcon(
                      Iconsax.arrow_right,
                      size: 13,
                      color: colors.textPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
