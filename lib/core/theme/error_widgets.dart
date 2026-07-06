import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../extensions/build_context_l10n.dart';
import 'tokens/domain_aliases.dart';

/// Reusable error state widget for network/connection errors.
///
/// Uses a private `_IconTint` enum to express "which theme role drives the
/// icon color" without pinning a literal `Color` at construction time. The
/// tint resolves against the active theme inside [build].
enum _IconTint { warning, secondary }

class NetworkErrorWidget extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  /// Explicit override for the icon color. When null, [_iconTint] drives it.
  final Color? iconColor;
  final _IconTint _iconTint;

  const NetworkErrorWidget({
    super.key,
    this.title = 'Connection Issue',
    this.message =
        'Unable to load data. Please check your internet connection and try again.',
    this.onRetry,
    this.icon = Iconsax.wifi_square,
    this.iconColor,
  }) : _iconTint = _IconTint.warning;

  const NetworkErrorWidget._withTint({
    required this.title,
    required this.message,
    this.onRetry,
    required this.icon,
    required _IconTint tint,
  })  : iconColor = null,
        _iconTint = tint;

  /// Factory for generic loading error.
  ///
  /// [customTitle]/[customMessage] let callers supply already-localized copy so
  /// the widget can be adopted on real (user-facing) error sites without
  /// leaking the English defaults into other locales.
  factory NetworkErrorWidget.loadingError({
    String? customTitle,
    String? customMessage,
    VoidCallback? onRetry,
  }) {
    return NetworkErrorWidget._withTint(
      title: customTitle ?? 'Something Went Wrong',
      message: customMessage ?? 'We couldn\'t load the data. Please try again.',
      onRetry: onRetry,
      icon: Iconsax.warning_2,
      tint: _IconTint.warning,
    );
  }

  /// Factory for offline state
  factory NetworkErrorWidget.offline({VoidCallback? onRetry}) {
    return NetworkErrorWidget._withTint(
      title: 'You\'re Offline',
      message: 'Please check your internet connection and try again.',
      onRetry: onRetry,
      icon: Iconsax.wifi_square,
      tint: _IconTint.secondary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedIconColor = iconColor ??
        switch (_iconTint) {
          _IconTint.warning => context.colors.warning,
          _IconTint.secondary => context.colors.textSecondary,
        };
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.spacing.space32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: resolvedIconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 40, color: resolvedIconColor),
            ),
            SizedBox(height: context.spacing.space24),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: context.colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: context.spacing.space8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(height: context.spacing.space24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Iconsax.refresh),
                label: Text(context.l10n.commonRetry),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: context.colors.textOnPrimary,
                  padding: EdgeInsets.symmetric(
                    horizontal: context.spacing.space24,
                    vertical: context.spacing.space12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact inline error widget for smaller spaces
class InlineErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const InlineErrorWidget({
    super.key,
    this.message = 'Unable to load',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(context.spacing.space16),
      decoration: BoxDecoration(
        color: context.colors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
      ),
      child: Row(
        children: [
          Icon(Iconsax.warning_2, color: context.colors.warning, size: 20),
          SizedBox(width: context.spacing.space12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.commonRetry),
            ),
        ],
      ),
    );
  }
}
