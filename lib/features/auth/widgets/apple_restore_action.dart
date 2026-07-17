import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../groups/providers/group_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/shell_emptiness_gate.dart';
import '../services/auth_recovery_service.dart';

/// Triggers the #1256 Apple restore (cross-UID discard-shell swap) from a
/// restore entry point — the Apple sibling of [triggerGoogleRestore].
///
/// On success the swap performs a true app restart, so this never returns to
/// the calling UI. A user-dismissed Apple sheet
/// ([AuthorizationErrorCode.canceled]) is silent — the credential is obtained
/// BEFORE any isolation/auth change, so a cancel leaves the anon shell fully
/// intact. Any other error (no identityToken, a failed sign-in) surfaces a
/// snackbar.
Future<void> triggerAppleRestore(BuildContext context, WidgetRef ref) async {
  // #648: this is an irreversible cross-UID discard-shell swap, and un-gating
  // join means an anonymous shell can now hold real ledger data. The CTA's
  // visibility gate (userGroupsProvider empty) FALSE-EMPTIES on the cold-start
  // firebaseUserProvider race (AsyncLoading → Stream.value([]) → AsyncData([])),
  // so guard the SWAP itself, not just the CTA. Block unless the outgoing shell
  // is provably empty — the same defer-then-decide gate the #647 email-recover
  // path uses (resolves the UID FIRST, fail-safe → block).
  final shellEmpty = await outgoingShellProvablyEmpty(
    readUser: () => ref.read(firebaseUserProvider.future),
    readGroups: () => ref.read(userGroupsProvider.future),
    probeHasLiveData: ref.read(shellEmptinessServerProbeProvider),
    timeout: ref.read(shellEmptinessGateTimeoutProvider),
  );
  if (!shellEmpty) {
    if (!context.mounted) return;
    _snack(context, context.l10n.restoreBlockedHasData);
    return;
  }
  try {
    await ref.read(authRecoveryServiceProvider).restoreWithApple();
    // success path restarts the app — nothing to do here.
  } on SignInWithAppleAuthorizationException catch (e) {
    if (e.code == AuthorizationErrorCode.canceled) return;
    if (!context.mounted) return;
    _snack(context, context.l10n.restoreAppleFailed);
  } on PendingWritesNotFlushedException {
    if (!context.mounted) return;
    _snack(context, context.l10n.restorePendingWritesNotSynced);
  } catch (_) {
    if (!context.mounted) return;
    _snack(context, context.l10n.restoreAppleFailed);
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
}
