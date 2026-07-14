import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../auth/services/data_deletion_service.dart';
import '../../../auth/services/durable_account_marker.dart';
import '../../../auth/widgets/delete_account_dialog.dart';
import '../../../auth/widgets/delete_account_retry_dialog.dart';
import '../../../auth/widgets/durable_shell_delete_dialog.dart';
import '../../keys/profile_keys.dart';
import 'pref_icon.dart';
import 'pref_row.dart';
import 'rows_card.dart';

/// Delete account, isolated in its own labelled "Danger" block so the single
/// irreversible action never sits inline with the benign credential/recovery
/// rows (#487 bullet 3 — restore/recovery grouped above, delete fenced here).
class DangerZoneCard extends ConsumerWidget {
  const DangerZoneCard({super.key});

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    // #469: an anonymous shell delete only removes this guest session, not any
    // durable Google/email account (which lives under a different UID). Make
    // the confirm dialog honest about that.
    final isAnonymous =
        ref.read(authUserChangesProvider).valueOrNull?.isAnonymous ?? false;
    // #469 prevention: if a durable account was established on this device but
    // the live session is an anon shell, deleting now would silently leave that
    // account + its data intact under a different uid. Steer to sign-in first,
    // with an explicit informed escape — never call deleteAccount on the shell
    // unless the user picks "delete just this guest session".
    if (isAnonymous &&
        durableAccountEstablished(ref.read(sharedPreferencesProvider))) {
      final choice = await DurableShellDeleteDialog.show(context);
      if (choice == DurableShellDeleteChoice.deleteGuest && context.mounted) {
        await _runDeletion(context, ref);
      }
      return;
    }
    final confirmed = await DeleteAccountDialog.show(
      context,
      isAnonymous: isAnonymous,
    );
    if (confirmed != true || !context.mounted) return;
    await _runDeletion(context, ref);
  }

  /// Runs the deletion and reacts to the outcome. A [DeletionResult.partial]
  /// (server scrubbed some data but threw before finishing; convergent on
  /// retry) re-prompts with a durable retry dialog and recurses on confirm, so
  /// the user always has a guaranteed path to finish a torn deletion (#77).
  Future<void> _runDeletion(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final result = await ref.read(dataDeletionServiceProvider).deleteAccount();
    if (!context.mounted) return;
    switch (result) {
      case DeletionResult.ok:
        messenger.showSnackBar(SnackBar(content: Text(l10n.profileDeletionOk)));
        context.go(AppRoutes.home);
      case DeletionResult.noUser:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.profileDeletionNoUser)),
        );
      case DeletionResult.error:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.profileDeletionError)),
        );
      case DeletionResult.partial:
        final retry = await DeleteAccountRetryDialog.show(context);
        if (retry == true && context.mounted) {
          await _runDeletion(context, ref);
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
      child: RowsCard(
        key: ProfileKeys.dangerZoneCard,
        rows: [
          PrefRow(
            tileKey: ProfileKeys.deleteAccountTile,
            leading: PrefIcon(icon: Iconsax.trash, bg: colors.cardSoft),
            label: context.l10n.profileAccountDelete,
            trailing: Text(
              context.l10n.profileAccountDeletePermanent,
              style: AppTypography.sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.error,
              ),
            ),
            onTap: () => _deleteAccount(context, ref),
            divider: false,
          ),
        ],
      ),
    );
  }
}
