import 'package:flutter/material.dart';

import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

/// Hero card for the Vault screen (D-14).
///
/// Shows file count, total size, and Upload File CTA.
class VaultHeroCard extends StatelessWidget {
  final int fileCount;
  final String totalSize;
  final VoidCallback onUpload;

  const VaultHeroCard({
    super.key,
    required this.fileCount,
    required this.totalSize,
    required this.onUpload,
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
            'DOCUMENTS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColorTokens.light.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          // File count · size heading
          Text(
            '$fileCount files · $totalSize',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColorTokens.light.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          // Upload File CTA
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onUpload,
              child: const Text('Upload File'),
            ),
          ),
        ],
      ),
    );
  }
}
