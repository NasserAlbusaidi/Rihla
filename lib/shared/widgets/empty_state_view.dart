import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/keys/shared_keys.dart';
import '../../core/theme/tokens/color_tokens.dart';

class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;
  final LinearGradient? accentGradient;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.iconColor,
    this.accentGradient,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppColorTokens.light.textMuted;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    Widget result = Center(
      key: SharedKeys.emptyStateView,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
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
                      borderRadius: BorderRadius.circular(16),
                    ),
              child: Icon(
                icon,
                size: 48,
                color: accentGradient != null ? Colors.white : color,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColorTokens.light.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColorTokens.light.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  key: SharedKeys.emptyStateCtaButton,
                  onPressed: onAction,
                  child: Text(actionLabel!),
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
