import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/email_validators.dart';
import '../../groups/providers/group_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/sign_out_first_dialog.dart';

/// Home empty state → "I had Rihla before — restore" entry.
///
/// Spec §4.2 + plan §P4. The user enters their previously-linked email,
/// the app sends a sign-in link via [AuthRecoveryService.sendRecoveryLink],
/// and the deep-link bootstrap completes recovery on tap.
///
/// FR-REC-2: if the device has any owned groups (proxy for owned
/// participant docs), recovery is refused unless the user confirms the
/// sign-out-first dialog.
class RecoverScreen extends ConsumerStatefulWidget {
  const RecoverScreen({super.key});

  @override
  ConsumerState<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends ConsumerState<RecoverScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _sending = false;
  String? _serverError;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<bool> _confirmIfDevicePopulated() async {
    final groups = ref.read(userGroupsProvider).valueOrNull ?? const [];
    if (groups.isEmpty) return true;
    final confirmed = await SignOutFirstDialog.show(context);
    if (confirmed != true) return false;
    try {
      // No linked email yet on this device — sign out the anon UID and
      // mint a fresh one before sending the recovery link. This mirrors
      // signOutCurrentDevice() but skips the linked-email guard.
      await ref.read(firebaseAuthProvider).signOut();
    } catch (_) {
      // signOut should not realistically fail; continue regardless and
      // let the recovery flow surface any auth failure.
    }
    return true;
  }

  Future<void> _send() async {
    setState(() => _serverError = null);
    if (!_formKey.currentState!.validate()) return;

    final ok = await _confirmIfDevicePopulated();
    if (!ok) return;

    final email = normalizeEmail(_emailController.text);
    setState(() => _sending = true);
    try {
      await ref.read(authRecoveryServiceProvider).sendRecoveryLink(email);
      if (!mounted) return;
      context.go(
        Uri(
          path: AppRoutes.recoverPending,
          queryParameters: {'email': email},
        ).toString(),
      );
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
      case 'user-not-found':
      case 'invalid-email':
        return "We couldn't find a Rihla account with this email. "
            'Make sure you linked it on your previous device first.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a few minutes and try again.';
      case 'network-request-failed':
        return 'No connection. Check your internet and try again.';
      default:
        return 'Something went wrong (${error.code}). Please try again.';
    }
  }

  void _back() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(AppRoutes.home);
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
    // Watching the provider ensures it's subscribed so _confirmIfDevicePopulated
    // can read a populated value via ref.read; otherwise valueOrNull would
    // be null on first read and the dialog would never show.
    ref.watch(userGroupsProvider);
    final colors = context.colors;
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
          'Restore from email',
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
                'Welcome back',
                style: AppTypography.sans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the email you linked on your old device. '
                "We'll send a one-tap sign-in link.",
                style: AppTypography.sans(
                  fontSize: 14,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                key: const Key('recover.email'),
                controller: _emailController,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'you@example.com',
                ),
                validator: validateEmail,
                onFieldSubmitted: (_) => _send(),
              ),
              if (_serverError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _serverError!,
                  key: const Key('recover.error'),
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
                  key: const Key('recover.submit'),
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Send recovery link'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
