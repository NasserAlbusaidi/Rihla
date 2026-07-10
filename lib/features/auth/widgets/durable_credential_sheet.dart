import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:iconsax/iconsax.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../groups/providers/group_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/shell_emptiness_gate.dart';
import '../services/durable_credential_exception.dart';

/// Optional credential sheet shown from account-link prompts.
///
/// Returns `true` only after the Google credential is linked to the current
/// anonymous user AND the ID token is force-refreshed so downstream auth
/// observers see the durable credential immediately. `false` for "Not now" or
/// a barrier dismiss.
///
/// On a link conflict ([GoogleLinkConflictException]) the sheet offers
/// "switch to that account" (#428) — a discard-shell `restoreWithGoogle`
/// reusing the failed credential — but ONLY when [outgoingShellProvablyEmpty]
/// proves the current shell empty.
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
  bool _restoring = false;
  String? _errorText;
  GoogleLinkConflictException? _conflict;
  GoogleLinkConflictException? _conflictShellGateOwner;
  Future<bool>? _conflictShellGate;

  Future<void> _continueWithGoogle() async {
    setState(() {
      _linking = true;
      _errorText = null;
      _clearConflict();
    });
    try {
      final result = await ref
          .read(authRecoveryServiceProvider)
          .linkGoogleToCurrentUser();
      // The cached ID token can still report the pre-link provider until the
      // SDK refreshes it lazily. Refresh now so link completion is observable.
      await result.user?.getIdToken(true);
      if (mounted) Navigator.of(context).pop(true);
    } on GoogleSignInException {
      // Canceled/interrupted Credential Manager sheet — silent reset.
      if (mounted) setState(() => _linking = false);
    } on GoogleLinkConflictException catch (e) {
      // PII-safe trail (#439): conflict code only.
      unawaited(
        Sentry.addBreadcrumb(
          Breadcrumb(
            category: 'auth.gate',
            message: 'link conflict code=${e.cause.code}',
          ),
        ),
      );
      // The switch decision is gated by outgoingShellProvablyEmpty (#648) and
      // is NEVER resolved by signing the anon user out (#213).
      if (!mounted) return;
      setState(() {
        _linking = false;
        _conflict = e;
        _conflictShellGateOwner = null;
        _conflictShellGate = null;
      });
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked') {
        // The gate fired on a stale isAnonymous read — this user already has
        // Google linked. Refresh the token and treat as success.
        try {
          await FirebaseConfig.currentUser?.getIdToken(true);
        } catch (_) {
          // No-Firebase tests / offline: the rules backstop still governs.
        }
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      if (!mounted) return;
      setState(() {
        _linking = false;
        _errorText = switch (e.code) {
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

  /// Discard-shell switch (#428): restore the existing Google-backed account
  /// with the credential that just failed to link. On success this never
  /// returns — the isolation protocol restarts the app. Only reachable when
  /// the shell is provably empty.
  Future<void> _switchAccount() async {
    final conflict = _conflict;
    if (conflict == null || _restoring) return;
    setState(() => _restoring = true);
    try {
      if (!await _outgoingShellEmpty()) {
        if (!mounted) return;
        setState(() {
          _restoring = false;
          _errorText = context.l10n.durableGateConflict;
          _clearConflict();
        });
        return;
      }
      await ref
          .read(authRecoveryServiceProvider)
          .restoreWithGoogle(credential: conflict.credential);
    } catch (e, st) {
      // Only pre-isolation failures reach here (a post-isolation failure
      // dies in the guaranteed restart). The anon shell is intact.
      unawaited(Sentry.captureException(e, stackTrace: st));
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _clearConflict();
        _errorText = context.l10n.durableGateError;
      });
    }
  }

  void _clearConflict() {
    _conflict = null;
    _conflictShellGateOwner = null;
    _conflictShellGate = null;
  }

  Future<bool> _outgoingShellEmpty() {
    return outgoingShellProvablyEmpty(
      readUser: () => ref.read(firebaseUserProvider.future),
      readGroups: () => ref.read(userGroupsProvider.future),
      probeHasLiveData: ref.read(shellEmptinessServerProbeProvider),
      timeout: ref.read(shellEmptinessGateTimeoutProvider),
    );
  }

  Future<bool> _conflictShellEmpty(GoogleLinkConflictException conflict) {
    if (!identical(_conflictShellGateOwner, conflict)) {
      _conflictShellGateOwner = conflict;
      _conflictShellGate = _outgoingShellEmpty();
    }
    return _conflictShellGate!;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final conflict = _conflict;

    if (conflict == null) {
      return _sheetShell(children: _initialContent(errorText: _errorText));
    }

    // Conflict state: switch visibility is derived from the same guard used at
    // the irreversible swap. Loading → progress; false/error/timeout → dead-end.
    return FutureBuilder<bool>(
      future: _conflictShellEmpty(conflict),
      builder: (context, snapshot) => _sheetShell(
        children:
            snapshot.connectionState == ConnectionState.done &&
                snapshot.data == true
            ? _switchOfferContent()
            : snapshot.connectionState == ConnectionState.done
            ? _initialContent(errorText: l10n.durableGateConflict)
            : _conflictLoadingContent(),
      ),
    );
  }

  Widget _sheetShell({required List<Widget> children}) {
    final colors = context.colors;
    final spacing = context.spacing;
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
            ...children,
          ],
        ),
      ),
    );
  }

  List<Widget> _initialContent({String? errorText}) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l10n = context.l10n;
    return [
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
      if (errorText != null) ...[
        SizedBox(height: spacing.space12),
        Text(
          errorText,
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
            child: _secondaryButton(
              label: l10n.durableGateNotNow,
              onPressed: _linking
                  ? null
                  : () => Navigator.of(context).pop(false),
            ),
          ),
          SizedBox(width: spacing.space12),
          Expanded(
            child: _primaryButton(
              key: const Key('durableGate.continue'),
              label: l10n.durableGateContinueGoogle,
              busy: _linking,
              onPressed: _linking ? null : _continueWithGoogle,
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _conflictLoadingContent() {
    final spacing = context.spacing;
    return [
      Text(
        context.l10n.durableGateConflictTitle,
        style: AppTypography.sans(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: context.colors.textPrimary,
        ),
      ),
      SizedBox(height: spacing.space24),
      const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              key: Key('durableGate.conflictLoading'),
              strokeWidth: 2.5,
            ),
          ),
        ),
      ),
      SizedBox(height: spacing.space12),
    ];
  }

  List<Widget> _switchOfferContent() {
    final colors = context.colors;
    final spacing = context.spacing;
    final l10n = context.l10n;
    return [
      Text(
        l10n.durableGateConflictTitle,
        style: AppTypography.sans(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
      SizedBox(height: spacing.space8),
      Text(
        l10n.durableGateConflictSwitchBody,
        style: AppTypography.sans(
          fontSize: 14,
          height: 1.4,
          color: colors.textSecondary,
        ),
      ),
      SizedBox(height: spacing.space24),
      Row(
        children: [
          Expanded(
            child: _secondaryButton(
              label: l10n.durableGateUseDifferent,
              onPressed: _restoring
                  ? null
                  : () => setState(() => _conflict = null),
            ),
          ),
          SizedBox(width: spacing.space12),
          Expanded(
            child: _primaryButton(
              key: const Key('durableGate.switch'),
              label: l10n.durableGateSwitch,
              busy: _restoring,
              onPressed: _restoring ? null : _switchAccount,
            ),
          ),
        ],
      ),
      SizedBox(height: spacing.space8),
      Center(
        child: TextButton(
          onPressed: _restoring ? null : () => Navigator.of(context).pop(false),
          child: Text(
            l10n.durableGateNotNow,
            style: AppTypography.sans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    ];
  }

  Widget _secondaryButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    final colors = context.colors;
    final spacing = context.spacing;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(spacing.radiusMedium),
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppTypography.sans(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: colors.textSecondary,
        ),
      ),
    );
  }

  Widget _primaryButton({
    required Key key,
    required String label,
    required bool busy,
    required VoidCallback? onPressed,
  }) {
    final colors = context.colors;
    final spacing = context.spacing;
    return ElevatedButton(
      key: key,
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.textOnPrimary,
        elevation: 0,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(spacing.radiusMedium),
        ),
      ),
      child: busy
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colors.textOnPrimary,
              ),
            )
          : Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.sans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.textOnPrimary,
              ),
            ),
    );
  }
}
