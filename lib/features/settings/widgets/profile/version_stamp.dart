import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_metadata.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../keys/profile_keys.dart';

class VersionStamp extends ConsumerWidget {
  const VersionStamp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final meta = ref.watch(appMetadataProvider).valueOrNull;
    final version = meta?.version ?? '';
    // Intentional brand lockup — stays English in every locale, including
    // Arabic (#162 decision: brand lockup, not localized). Do NOT route this
    // through l10n; pinned by profile_screen_test '#162'.
    return Padding(
      key: ProfileKeys.versionTile,
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        version.isEmpty
            ? 'RIHLA · BUILT FOR JOURNEYS'
            : 'RIHLA · v$version · BUILT FOR JOURNEYS',
        style: AppTypography.mono(
          fontSize: 9,
          color: colors.textSecondary,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
