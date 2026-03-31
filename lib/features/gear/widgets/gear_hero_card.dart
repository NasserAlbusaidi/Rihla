import 'package:flutter/material.dart';

import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

/// Hero card for the Gear screen (D-12).
///
/// Shows packed progress, priority item count badge, and Add Item CTA.
class GearHeroCard extends StatelessWidget {
  final int packedCount;
  final int totalCount;
  final int priorityCount;
  final VoidCallback onAddItem;

  const GearHeroCard({
    super.key,
    required this.packedCount,
    required this.totalCount,
    required this.priorityCount,
    required this.onAddItem,
  });

  @override
  Widget build(BuildContext context) {
    final progress =
        totalCount > 0 ? (packedCount / totalCount).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        8,
      ),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColorTokens.light.cardSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadowTokens.standard.raised,
        image: const DecorationImage(
          image: AssetImage('assets/textures/grain.png'),
          repeat: ImageRepeat.repeat,
          opacity: 0.035,
          fit: BoxFit.none,
          alignment: Alignment.topLeft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overline
          Text(
            'PACKING PROGRESS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColorTokens.light.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          // Packed count heading
          Text(
            'Packed $packedCount/$totalCount',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColorTokens.light.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          // Progress bar
          LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: AppColorTokens.light.border,
            valueColor: AlwaysStoppedAnimation(AppColorTokens.light.moduleLedger),
            borderRadius: BorderRadius.circular(2),
          ),
          if (priorityCount > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColorTokens.light.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$priorityCount priority',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColorTokens.light.errorText,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Add Item CTA
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onAddItem,
              child: const Text('Add Item'),
            ),
          ),
        ],
      ),
    );
  }
}
