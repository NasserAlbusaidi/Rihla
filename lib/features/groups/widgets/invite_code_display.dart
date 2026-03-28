import 'package:flutter/material.dart';

import '../../../core/keys/shared_keys.dart';
import '../../../core/theme/app_theme.dart';

/// Widget that displays a formatted invite code in a mintSurface pill.
///
/// Shows the code in a large, spaced format. Optionally renders copy
/// and share action buttons below the pill.
class InviteCodeDisplay extends StatelessWidget {
  final String code;
  final VoidCallback? onCopy;
  final VoidCallback? onShare;

  const InviteCodeDisplay({
    super.key,
    required this.code,
    this.onCopy,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final hasActions = onCopy != null || onShare != null;

    return Column(
      key: SharedKeys.inviteCodeDisplay,
      children: [
        // Code pill
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppColors.space24,
            vertical: AppColors.space16,
          ),
          decoration: BoxDecoration(
            color: AppColors.mintSurface,
            borderRadius: BorderRadius.circular(AppColors.radiusSmall),
          ),
          child: Center(
            child: Text(
              code,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 8,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        // Action buttons (copy + share)
        if (hasActions) ...[
          const SizedBox(height: AppColors.space16),
          Row(
            children: [
              if (onCopy != null)
                Expanded(
                  child: SizedBox(
                    height: AppColors.buttonHeight,
                    child: ElevatedButton(
                      key: SharedKeys.inviteCodeCopyButton,
                      onPressed: onCopy,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                        ),
                      ),
                      child: const Text('Copy Code'),
                    ),
                  ),
                ),
              if (onCopy != null && onShare != null)
                const SizedBox(width: AppColors.space12),
              if (onShare != null)
                Expanded(
                  child: SizedBox(
                    height: AppColors.buttonHeight,
                    child: OutlinedButton(
                      key: SharedKeys.inviteCodeShareButton,
                      onPressed: onShare,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                        ),
                      ),
                      child: const Text('Share'),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
