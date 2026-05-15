import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../providers/auth_provider.dart';

/// "Check your inbox" interstitial after a link send.
///
/// Plan §P3 + spec risk row 3 (deliverability): a 60-second resend cooldown
/// keeps the user from spamming the daily quota while their email client
/// catches up. The address is carried in the route query so the interstitial
/// can be restored without relying on GoRouter `extra` state.
class LinkEmailSentScreen extends ConsumerStatefulWidget {
  const LinkEmailSentScreen({super.key, required this.email});
  final String email;

  @override
  ConsumerState<LinkEmailSentScreen> createState() =>
      _LinkEmailSentScreenState();
}

class _LinkEmailSentScreenState extends ConsumerState<LinkEmailSentScreen> {
  static const _resendCooldown = Duration(seconds: 60);

  Timer? _ticker;
  int _remainingSeconds = _resendCooldown.inSeconds;
  bool _resending = false;
  String? _statusMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startCooldown();
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
          .linkEmailToCurrentUser(widget.email);
      if (!mounted) return;
      setState(() => _statusMessage = 'New link sent.');
      _startCooldown();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = "Couldn't resend (${error.code}).");
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = "Couldn't resend. Try again in a bit.");
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _done() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canResend = _remainingSeconds == 0 && !_resending;

    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: colors.scaffoldBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Iconsax.close_square),
          onPressed: _done,
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
                'Check your inbox',
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
                    const TextSpan(text: 'We sent a sign-in link to '),
                    TextSpan(
                      text: widget.email,
                      style: AppTypography.sans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const TextSpan(
                      text: '. Tap it on this device to finish linking.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Can't find it? Check your spam folder. The link is good for 24 hours.",
                style: AppTypography.sans(
                  fontSize: 13,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _statusMessage!,
                  key: const Key('linkEmailSent.status'),
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
                  key: const Key('linkEmailSent.error'),
                  style: AppTypography.sans(fontSize: 13, color: colors.error),
                ),
              ],
              const Spacer(),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  key: const Key('linkEmailSent.resend'),
                  onPressed: canResend ? _resend : null,
                  child: _resending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(
                          canResend
                              ? 'Resend link'
                              : 'Resend in ${_remainingSeconds}s',
                        ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: FilledButton(
                  key: const Key('linkEmailSent.done'),
                  onPressed: _done,
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
