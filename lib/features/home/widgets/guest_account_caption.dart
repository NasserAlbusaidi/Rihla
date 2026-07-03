import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../auth/providers/auth_provider.dart';
import '../keys/home_keys.dart';

/// Persistent, non-dismissible one-line reminder that an anonymous account
/// lives only on this device (#818 Wave 4.3).
///
/// The #285 [AccountBackupNudge] explains the same fact, but it can be
/// dismissed forever — after that, nothing on Home says the data is
/// device-bound (the amber pill only exists on Profile). This caption is the
/// residue that survives the nudge's dismissal: shown while anonymous, gone
/// once a durable credential is linked, never gated on a dismiss flag.
class GuestAccountCaption extends ConsumerWidget {
  const GuestAccountCaption({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDurable = ref.watch(isDurableUserProvider);
    if (isDurable) return const SizedBox.shrink();

    final colors = context.colors;
    return Padding(
      key: HomeKeys.guestAccountCaption,
      padding: const EdgeInsetsDirectional.fromSTEB(20, 6, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Iconsax.shield_tick, size: 13, color: colors.textSecondary),
          SizedBox(width: context.spacing.space4),
          Expanded(
            child: Text(
              context.l10n.homeGuestCaption,
              style: AppTypography.sans(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
