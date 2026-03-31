import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

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
        AppColors.space16,
        AppColors.space16,
        AppColors.space16,
        AppColors.space8,
      ),
      padding: const EdgeInsets.all(AppColors.space20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.radiusLarge),
        boxShadow: AppColors.cardShadow,
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
          const Text(
            'DOCUMENTS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppColors.space8),
          // File count · size heading
          Text(
            '$fileCount files · $totalSize',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppColors.space16),
          // Upload File CTA
          SizedBox(
            width: double.infinity,
            height: AppColors.buttonHeight,
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
