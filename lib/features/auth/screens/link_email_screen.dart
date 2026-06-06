import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
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
/// the "check your inbox" screen with the email in the URL query so the
/// confirmation page survives restoration and deep-link entry.
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
    if (normalizeEmail(input ?? '') != normalizeEmail(_emailController.text)) {
      return context.l10n.authErrorEmailsDontMatch;
    }
    return null;
  }

  Future<void> _send() async {
    setState(() => _serverError = null);
    if (!_formKey.currentState!.validate()) return;

    final email = normalizeEmail(_emailController.text);
    setState(() => _sending = true);
    try {
      await ref.read(authRecoveryServiceProvider).linkEmailToCurrentUser(email);
      if (!mounted) return;
      context.go(
        Uri(
          path: AppRoutes.linkEmailSent,
          queryParameters: {'email': email},
        ).toString(),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _serverError = _humanizeError(context, error));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _serverError = context.l10n.authErrorSendLink;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _humanizeError(BuildContext context, FirebaseAuthException error) {
    final l10n = context.l10n;
    switch (error.code) {
      case 'credential-already-in-use':
      case 'email-already-in-use':
      case 'provider-already-linked':
        return l10n.authErrorEmailAlreadyLinked;
      case 'invalid-email':
        return l10n.authErrorInvalidEmail;
      case 'too-many-requests':
        return l10n.authErrorRateLimited;
      case 'network-request-failed':
        return l10n.authErrorOffline;
      default:
        return l10n.authErrorGeneric(error.code);
    }
  }

  void _back() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(AppRoutes.profile);
      }
      return;
    }

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: colors.scaffoldBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left_2),
          onPressed: _back,
        ),
        title: Text(
          l10n.authLinkEmailTitle,
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
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space20, vertical: context.spacing.space16),
            children: [
              Text(
                l10n.authLinkEmailHeading,
                style: AppTypography.sans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              SizedBox(height: context.spacing.space8),
              Text(
                l10n.authLinkEmailDescription,
                style: AppTypography.sans(
                  fontSize: 14,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
              SizedBox(height: context.spacing.space24),
              TextFormField(
                key: const Key('linkEmail.email'),
                controller: _emailController,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.commonEmail,
                  hintText: l10n.commonEmailHintExample,
                ),
                validator: validateEmail,
              ),
              SizedBox(height: context.spacing.space16),
              TextFormField(
                key: const Key('linkEmail.confirm'),
                controller: _confirmController,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: l10n.authLinkEmailConfirmLabel,
                ),
                validator: _validateConfirm,
                onFieldSubmitted: (_) => _send(),
              ),
              SizedBox(height: context.spacing.space16),
              Container(
                padding: EdgeInsets.all(context.spacing.space12),
                decoration: BoxDecoration(
                  color: colors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l10n.authLinkEmailPrivacyNote,
                  style: AppTypography.sans(
                    fontSize: 12,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
              if (_serverError != null) ...[
                SizedBox(height: context.spacing.space12),
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
              SizedBox(height: context.spacing.space24),
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
                      : Text(l10n.authLinkEmailSubmit),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
