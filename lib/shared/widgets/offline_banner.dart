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
    final isOffline = status == ConnectivityStatus.offline;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: isOffline
          ? Container(
              key: SharedKeys.offlineBanner,
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: context.spacing.space16,
                vertical: context.spacing.space8,
              ),
              color: context.colors.warning.withValues(alpha: 0.12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 16,
                    color: context.colors.warning,
                  ),
                  SizedBox(width: context.spacing.space8),
                  Text(
                    context.l10n.offlineBannerMessage,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.colors.warning,
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
