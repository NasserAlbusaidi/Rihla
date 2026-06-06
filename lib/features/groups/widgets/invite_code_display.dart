import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/keys/shared_keys.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

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
          padding: EdgeInsets.symmetric(horizontal: context.spacing.space24, vertical: context.spacing.space16),
          decoration: BoxDecoration(
            color: context.colors.selectionFill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              code,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 8,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ),
        // Action buttons (copy + share)
        if (hasActions) ...[
          SizedBox(height: context.spacing.space16),
          Row(
            children: [
              if (onCopy != null)
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      key: SharedKeys.inviteCodeCopyButton,
                      onPressed: onCopy,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(context.l10n.groupCopyCode),
                    ),
                  ),
                ),
              if (onCopy != null && onShare != null) SizedBox(width: context.spacing.space12),
              if (onShare != null)
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      key: SharedKeys.inviteCodeShareButton,
                      onPressed: onShare,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(context.l10n.groupShare),
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
