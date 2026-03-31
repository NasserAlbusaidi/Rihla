import 'package:flutter/material.dart';

import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

/// Hero card for the Logistics screen (D-13).
///
/// Shows group/member stats, unassigned count, and Create Group CTA.
class LogisticsHeroCard extends StatelessWidget {
  final int groupCount;
  final int memberCount;
  final int unassignedCount;
  final VoidCallback onCreateGroup;

  const LogisticsHeroCard({
    super.key,
    required this.groupCount,
    required this.memberCount,
    required this.unassignedCount,
    required this.onCreateGroup,
  });

  @override
  Widget build(BuildContext context) {
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
            'ORGANIZATION',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColorTokens.light.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          // Groups · members heading
          Text(
            '$groupCount groups · $memberCount members',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColorTokens.light.textPrimary,
            ),
          ),
          if (unassignedCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$unassignedCount unassigned',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AppColorTokens.light.errorText,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Create Group CTA
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onCreateGroup,
              child: const Text('Create Group'),
            ),
          ),
        ],
      ),
    );
  }
}
