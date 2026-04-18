import 'package:flutter/material.dart';

import '../../../core/theme/tokens/domain_aliases.dart';

/// Stats hero card for the Logistics screen (D-22).
///
/// Shows group count, member count, and unassigned count. Contains a CTA
/// button that delegates to [onCreateTapped] — mutation stays on the screen.
class LogisticsHeroCard extends StatelessWidget {
  final int groupCount;
  final int memberCount;
  final int unassignedCount;
  final VoidCallback onCreateTapped;

  const LogisticsHeroCard({
    super.key,
    required this.groupCount,
    required this.memberCount,
    required this.unassignedCount,
    required this.onCreateTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.shadows.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ORGANIZATION',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: context.colors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$groupCount groups · $memberCount members',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
          ),
          if (unassignedCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$unassignedCount unassigned',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: context.colors.errorText,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onCreateTapped,
              child: const Text('Create Group'),
            ),
          ),
        ],
      ),
    );
  }
}
