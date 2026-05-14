import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/email_validators.dart';
import '../providers/auth_provider.dart';

/// Settings → "Linked email" → Set up.
///
/// Account-recovery spec §4.1 + plan §P3. The user enters an email twice
/// (typo guard per §10 risk register), the app calls
/// [AuthRecoveryService.linkEmailToCurrentUser], and on success routes to
/// the "check your inbox" screen with the email passed as `extra`.
class LinkEmailScreen extends ConsumerStatefulWidget {
  const LinkEmailScreen({super.key});

  @override
  ConsumerState<LinkEmailScreen> createState() => _LinkEmailScreenState();
}

class _LinkEmailScreenState extends ConsumerState<LinkEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _sending = false;
  String? _serverError;

  @override
  void dispose() {
    _emailController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validateConfirm(String? input) {
    final formatError = validateEmail(input);
    if (formatError != null) return formatError;
    if (normalizeEmail(input ?? '') !=
        normalizeEmail(_emailController.text)) {
      return "Emails don't match.";
    }
    return null;
  }

  Future<void> _send() async {
    setState(() => _serverError = null);
    if (!_formKey.currentState!.validate()) return;

    final email = normalizeEmail(_emailController.text);
    setState(() => _sending = true);
    try {
      await ref
          .read(authRecoveryServiceProvider)
          .linkEmailToCurrentUser(email);
      if (!mounted) return;
      context.go(AppRoutes.linkEmailSent, extra: email);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _serverError = _humanizeError(error));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _serverError =
            "Couldn't send the link. Check your connection and try again.";
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _humanizeError(FirebaseAuthException error) {
    switch (error.code) {
      case 'credential-already-in-use':
      case 'email-already-in-use':
      case 'provider-already-linked':
        return 'This email is already linked to a Rihla account. '
            'Restore from that account instead.';
      case 'invalid-email':
        return "That doesn't look like a valid email.";
      case 'too-many-requests':
        return 'Too many attempts. Wait a few minutes and try again.';
      case 'network-request-failed':
        return 'No connection. Check your internet and try again.';
      default:
        return 'Something went wrong (${error.code}). Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: colors.scaffoldBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left_2),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Link your email',
          style: AppTypography.sans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              Text(
                'So you can come back',
                style: AppTypography.sans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "We'll email you a one-tap sign-in link. If you ever lose "
                'your phone or clear app data, enter the same email on a new '
                'device to get all your trips back.',
                style: AppTypography.sans(
                  fontSize: 14,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                key: const Key('linkEmail.email'),
                controller: _emailController,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'you@example.com',
                ),
                validator: validateEmail,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('linkEmail.confirm'),
                controller: _confirmController,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Confirm email',
                ),
                validator: _validateConfirm,
                onFieldSubmitted: (_) => _send(),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Your email is used only to restore your Rihla data. '
                  "We don't send marketing email and we don't share it.",
                  style: AppTypography.sans(
                    fontSize: 12,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
              if (_serverError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _serverError!,
                  key: const Key('linkEmail.error'),
                  style: AppTypography.sans(
                    fontSize: 13,
                    color: colors.error,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton(
                  key: const Key('linkEmail.submit'),
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Send link'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
