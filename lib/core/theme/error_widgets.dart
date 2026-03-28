import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'app_theme.dart';

/// Reusable error state widget for network/connection errors
class NetworkErrorWidget extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;
  final Color iconColor;

  const NetworkErrorWidget({
    super.key,
    this.title = 'Connection Issue',
    this.message =
        'Unable to load data. Please check your internet connection and try again.',
    this.onRetry,
    this.icon = Iconsax.wifi_square,
    this.iconColor = AppColors.warning,
  });

  /// Factory for generic loading error
  factory NetworkErrorWidget.loadingError({
    String? customMessage,
    VoidCallback? onRetry,
  }) {
    return NetworkErrorWidget(
      title: 'Something Went Wrong',
      message: customMessage ?? 'We couldn\'t load the data. Please try again.',
      onRetry: onRetry,
      icon: Iconsax.warning_2,
      iconColor: AppColors.warning,
    );
  }

  /// Factory for offline state
  factory NetworkErrorWidget.offline({VoidCallback? onRetry}) {
    return NetworkErrorWidget(
      title: 'You\'re Offline',
      message: 'Please check your internet connection and try again.',
      onRetry: onRetry,
      icon: Iconsax.wifi_square,
      iconColor: AppColors.textSecondary,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 40, color: iconColor),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Iconsax.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Iconsax.warning_2, color: AppColors.amber, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
