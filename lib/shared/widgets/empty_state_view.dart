import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/keys/shared_keys.dart';
import '../../core/theme/tokens/domain_aliases.dart';

class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final IconData? secondaryActionIcon;
  final Color? iconColor;
  final LinearGradient? accentGradient;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.secondaryActionIcon,
    this.iconColor,
    this.accentGradient,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? context.colors.textSecondary;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    Widget result = Center(
      key: SharedKeys.emptyStateView,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(context.spacing.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: accentGradient != null
                  ? BoxDecoration(
                      gradient: accentGradient,
                      shape: BoxShape.circle,
                    )
                  : BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
                    ),
              child: Icon(
                icon,
                size: 48,
                // design-token-justified: on the accent-gradient badge the icon
                // is white over a saturated gradient in both themes; the
                // non-gradient branch already uses the themed token color.
                color: accentGradient != null ? Colors.white : color,
              ),
            ),
            SizedBox(height: context.spacing.space20),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: context.spacing.space8),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: context.spacing.space24),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  key: SharedKeys.emptyStateCtaButton,
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ),
            ],
            if (secondaryActionLabel != null && onSecondaryAction != null) ...[
              SizedBox(
                height: actionLabel != null
                    ? context.spacing.space12
                    : context.spacing.space24,
              ),
              SizedBox(
                height: 52,
                child: secondaryActionIcon != null
                    ? OutlinedButton.icon(
                        key: SharedKeys.emptyStateSecondaryCta,
                        onPressed: onSecondaryAction,
                        icon: Icon(secondaryActionIcon),
                        label: Text(secondaryActionLabel!),
                      )
                    : OutlinedButton(
                        key: SharedKeys.emptyStateSecondaryCta,
                        onPressed: onSecondaryAction,
                        child: Text(secondaryActionLabel!),
                      ),
              ),
            ],
          ],
        ),
      ),
    );

    if (!reduceMotion) {
      result = result.animate().fadeIn(duration: 400.ms).scale(
            begin: const Offset(0.95, 0.95),
            end: const Offset(1, 1),
            duration: 400.ms,
          );
    }

    return result;
  }
}
