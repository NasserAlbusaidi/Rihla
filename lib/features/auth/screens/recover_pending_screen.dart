import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../providers/auth_provider.dart';
import '../providers/auth_email_link_bootstrap_provider.dart';

/// Recovery counterpart to LinkEmailSentScreen — see spec §4.2 step 5+.
///
/// Watches [authUserChangesProvider]; when the bootstrap listener
/// completes recovery, the UID changes, the cache is wiped (P2), and the
/// user is auto-routed back home to find their restored data.
class RecoverPendingScreen extends ConsumerStatefulWidget {
  const RecoverPendingScreen({super.key, required this.email});
  final String email;

  @override
  ConsumerState<RecoverPendingScreen> createState() =>
      _RecoverPendingScreenState();
}

class _RecoverPendingScreenState extends ConsumerState<RecoverPendingScreen> {
  static const _resendCooldown = Duration(seconds: 60);

  Timer? _ticker;
  int _remainingSeconds = _resendCooldown.inSeconds;
  bool _resending = false;
  String? _statusMessage;
  String? _errorMessage;
  String? _initialUid;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _startCooldown();
    _initialUid = ref.read(uidProvider);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _remainingSeconds = _resendCooldown.inSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() => _remainingSeconds = 0);
      } else {
        setState(() => _remainingSeconds -= 1);
      }
    });
  }

  Future<void> _resend() async {
    if (_remainingSeconds > 0 || _resending) return;
    setState(() {
      _resending = true;
      _statusMessage = null;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authRecoveryServiceProvider)
          .sendRecoveryLink(widget.email);
      if (!mounted) return;
      setState(() => _statusMessage = context.l10n.authRecoverPendingResendStatus);
      _startCooldown();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage =
            context.l10n.authRecoverPendingResendErrorCode(error.code),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _errorMessage = context.l10n.authRecoverPendingResendErrorGeneric,
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _cancel() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final canResend = _remainingSeconds == 0 && !_resending;

    // When the bootstrap listener completes recovery, the UID flips. Watch
    // for that and route back home so the user sees their restored data.
    ref.listen<String?>(uidProvider, (previous, next) {
      if (_completed) return;
      if (next != null && next != _initialUid) {
        _completed = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.authWelcomeBack)),
        );
        context.go(AppRoutes.home);
      }
    });

    // Surface a "Confirm your email" prompt only if the bootstrap captured
    // a deep link but couldn't auto-complete (spec §4.7 different-device
    // case). Currently surfacing the link as a hint; the manual-prompt UI
    // is a P4+ follow-up.
    final pendingLink = ref.watch(pendingEmailLinkProvider);

    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: colors.scaffoldBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Iconsax.close_square),
          onPressed: _cancel,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colors.cardSurface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Iconsax.sms_tracking,
                  size: 26,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.authRecoverPendingTitle,
                style: AppTypography.sans(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  style: AppTypography.sans(
                    fontSize: 15,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                  children: [
                    TextSpan(text: l10n.authRecoverPendingDescriptionPrefix),
                    TextSpan(
                      text: widget.email,
                      style: AppTypography.sans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    TextSpan(text: l10n.authRecoverPendingDescriptionSuffix),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.authRecoverPendingSpamHint,
                style: AppTypography.sans(
                  fontSize: 13,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
              if (pendingLink != null) ...[
                const SizedBox(height: 16),
                Text(
                  l10n.authRecoverPendingLinkSeen,
                  key: const Key('recoverPending.linkSeen'),
                  style: AppTypography.sans(
                    fontSize: 13,
                    color: colors.primary,
                  ),
                ),
              ],
              if (_statusMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _statusMessage!,
                  key: const Key('recoverPending.status'),
                  style: AppTypography.sans(
                    fontSize: 13,
                    color: colors.primary,
                  ),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  key: const Key('recoverPending.error'),
                  style: AppTypography.sans(
                    fontSize: 13,
                    color: colors.error,
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  key: const Key('recoverPending.resend'),
                  onPressed: canResend ? _resend : null,
                  child: _resending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(
                          canResend
                              ? l10n.authRecoverPendingResendLink
                              : l10n.authRecoverPendingResendCountdown(
                                  _remainingSeconds,
                                ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: TextButton(
                  key: const Key('recoverPending.cancel'),
                  onPressed: _cancel,
                  child: Text(l10n.commonCancel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
