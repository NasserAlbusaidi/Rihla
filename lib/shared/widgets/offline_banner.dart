import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions/build_context_l10n.dart';
import '../../core/keys/shared_keys.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/theme/tokens/domain_aliases.dart';

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectivityProvider);

    // `online` collapses to nothing; `offline` and the transient `syncing`
    // ("Saved — will sync", #357) each render a tinted strip.
    final ({IconData icon, String message, Color color})? banner =
        switch (status) {
      ConnectivityStatus.offline => (
          icon: Icons.cloud_off_rounded,
          message: context.l10n.offlineBannerMessage,
          color: context.colors.warning,
        ),
      ConnectivityStatus.syncing => (
          icon: Icons.cloud_done_rounded,
          message: context.l10n.bannerSavedWillSync,
          color: context.colors.successText,
        ),
      ConnectivityStatus.online => null,
    };

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: banner == null
          ? const SizedBox.shrink()
          : Container(
              key: SharedKeys.offlineBanner,
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: context.spacing.space16,
                vertical: context.spacing.space8,
              ),
              color: banner.color.withValues(alpha: 0.12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(banner.icon, size: 16, color: banner.color),
                  SizedBox(width: context.spacing.space8),
                  Text(
                    banner.message,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: banner.color,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
