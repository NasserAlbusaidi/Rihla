import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:iconsax/iconsax.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../providers/auth_provider.dart';

/// Blocking gate sheet shown before the first valuable write (#441 PR2).
///
/// Returns `true` only after the Google credential is linked to the current
/// anonymous user AND the ID token is force-refreshed — the cached token can
/// still carry `sign_in_provider=anonymous` right after `linkWithCredential`,
/// and the very next write is rules-gated on it. `false` for "Not now" or a
/// barrier dismiss (the caller aborts the pending create/join).
Future<bool> showDurableCredentialSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _DurableCredentialSheet(),
  );
  return result ?? false;
}

class _DurableCredentialSheet extends ConsumerStatefulWidget {
  const _DurableCredentialSheet();

  @override
  ConsumerState<_DurableCredentialSheet> createState() =>
      _DurableCredentialSheetState();
}

class _DurableCredentialSheetState
    extends ConsumerState<_DurableCredentialSheet> {
  bool _linking = false;
  String? _errorText;

  Future<void> _continueWithGoogle() async {
    setState(() {
      _linking = true;
      _errorText = null;
    });
    try {
      final result = await ref
          .read(authRecoveryServiceProvider)
          .linkGoogleToCurrentUser();
      // The cached ID token can still say sign_in_provider=anonymous right
      // after linkWithCredential; the very next write is rules-gated on it.
      await result.user?.getIdToken(true);
      if (mounted) Navigator.of(context).pop(true);
    } on GoogleSignInException {
      // Canceled/interrupted Credential Manager sheet — silent reset.
      if (mounted) setState(() => _linking = false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _linking = false;
        // Conflicts are the caller's decision point (#441 PR3) — never
        // resolved here, and NEVER by signing the anon user out (#213).
        _errorText = switch (e.code) {
          'credential-already-in-use' ||
          'email-already-in-use' ||
          'provider-already-linked' => context.l10n.durableGateConflict,
          'network-request-failed' => context.l10n.authErrorOffline,
          _ => context.l10n.durableGateError,
        };
      });
    } catch (e, st) {
      unawaited(Sentry.captureException(e, stackTrace: st));
      if (!mounted) return;
      setState(() {
        _linking = false;
        _errorText = context.l10n.durableGateError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l10n = context.l10n;

    return SafeArea(
      child: Container(
        margin: EdgeInsets.fromLTRB(
          spacing.space16,
          0,
          spacing.space16,
          spacing.space16,
        ),
        padding: EdgeInsets.all(spacing.space24),
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(spacing.radiusLarge),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: spacing.space20),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colors.saffronTint,
                shape: BoxShape.circle,
              ),
              child: Icon(Iconsax.shield_tick, color: colors.primary),
            ),
            SizedBox(height: spacing.space16),
            Text(
              l10n.durableGateTitle,
              style: AppTypography.sans(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            SizedBox(height: spacing.space8),
            Text(
              l10n.durableGateBody,
              style: AppTypography.sans(
                fontSize: 14,
                height: 1.4,
                color: colors.textSecondary,
              ),
            ),
            if (_errorText != null) ...[
              SizedBox(height: spacing.space12),
              Text(
                _errorText!,
                key: const Key('durableGate.error'),
                style: AppTypography.sans(
                  fontSize: 13,
                  height: 1.35,
                  color: colors.error,
                ),
              ),
            ],
            SizedBox(height: spacing.space24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _linking
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          spacing.radiusMedium,
                        ),
                      ),
                    ),
                    child: Text(
                      l10n.durableGateNotNow,
                      style: AppTypography.sans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: spacing.space12),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('durableGate.continue'),
                    onPressed: _linking ? null : _continueWithGoogle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.textOnPrimary,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          spacing.radiusMedium,
                        ),
                      ),
                    ),
                    child: _linking
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: colors.textOnPrimary,
                            ),
                          )
                        : Text(
                            l10n.durableGateContinueGoogle,
                            style: AppTypography.sans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colors.textOnPrimary,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
