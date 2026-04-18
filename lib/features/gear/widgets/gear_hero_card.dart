import 'package:flutter/material.dart';

import '../../../core/theme/tokens/domain_aliases.dart';

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
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.shadows.raised,
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
              color: context.colors.textSecondary,
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
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          // Progress bar
          LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: context.colors.border,
            valueColor: AlwaysStoppedAnimation(context.colors.moduleLedger),
            borderRadius: BorderRadius.circular(2),
          ),
          if (priorityCount > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: context.colors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$priorityCount priority',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.colors.errorText,
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
