import 'package:flutter/material.dart';

import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

/// Hero card for the Memories screen — D-15.
///
/// Displays photo count, optional date range (pre-formatted), and an
/// "Add Photo" CTA button. No CTA shown when photoCount is 0 — the empty
/// state handles that case.
class MemoriesHeroCard extends StatelessWidget {
  /// Total number of photos uploaded to this event.
  final int photoCount;

  /// Pre-formatted date range string (e.g., "Mar 15 - Mar 28").
  /// Pass an empty string when there are no photos.
  final String dateRange;

  /// Called when the user taps "Add Photo".
  final VoidCallback onAddPhoto;

  const MemoriesHeroCard({
    super.key,
    required this.photoCount,
    required this.dateRange,
    required this.onAddPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        0,
      ),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColorTokens.light.cardSurface,
        borderRadius: BorderRadius.circular(16 + 8),
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
          // Row 1: "MEMORIES" overline
          Text(
            'MEMORIES',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColorTokens.light.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          // Row 2: photo count + optional date range
          _buildCountRow(),
          const SizedBox(height: 16),
          // Row 3: Add Photo CTA
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onAddPhoto,
              child: const Text('Add Photo'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountRow() {
    if (dateRange.isEmpty) {
      return Text(
        '0 photos',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColorTokens.light.textPrimary,
        ),
      );
    }

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$photoCount photos',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColorTokens.light.textPrimary,
            ),
          ),
          TextSpan(
            text: ' \u00b7 $dateRange',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColorTokens.light.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
