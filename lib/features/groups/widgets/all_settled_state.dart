import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../keys/group_keys.dart';
import '../../../core/theme/tokens/color_tokens.dart';

/// Empty-state widget displayed when all balances are settled.
///
/// Shows a success circle icon with "All settled up" heading and supporting text.
/// Extracted from [GroupSettleUpScreen._buildAllSettledState] (Phase 36 Plan 01).
class AllSettledState extends StatelessWidget {
  const AllSettledState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColorTokens.light.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Iconsax.tick_circle,
              color: AppColorTokens.light.success,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'All settled up',
            key: GroupKeys.settleUpAllSettledMessage,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColorTokens.light.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Everyone is square. No outstanding amounts.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColorTokens.light.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
