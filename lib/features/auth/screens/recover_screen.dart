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
import '../../../shared/widgets/directional_icon.dart';
import '../../groups/providers/group_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/merge_on_recover_dialog.dart';

/// Home empty state → "I had Rihla before — restore" entry.
///
/// Spec §4.2 + plan §P4. The user enters their previously-linked email,
/// the app sends a sign-in link via [AuthRecoveryService.sendRecoveryLink],
/// and the deep-link bootstrap completes recovery on tap.
///
/// Populated-device recovery MERGES (#427, superseding FR-REC-2's
/// sign-out-first): if the device has any groups, the user consents via
/// [MergeOnRecoverDialog] and the anon UID stays signed in — no sign-out,
/// no orphan. When the link is tapped, `completeRecovery` swaps to the
/// restored account and `cleanupAnonUidArtifacts` migrates this device's
/// data (`oldUid → newUid`) into it. See
/// docs/plans/2026-06-10-recovery-merge-reachable-restore.md.
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
    // No sign-out and no dirty-mark here: the populated anon UID must stay
    // signed in so completeRecovery can capture it as oldUid and merge its
    // data into the restored account (#427). Signing out first is how the
    // device's data got orphaned — by link-tap time the UID was gone.
    final confirmed = await MergeOnRecoverDialog.show(context);
    return confirmed == true;
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
      case 'user-not-found':
      case 'invalid-email':
        return l10n.authErrorAccountNotFound;
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
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: colors.scaffoldBackground,
        elevation: 0,
        leading: IconButton(
          icon: const DirectionalIcon(Iconsax.arrow_left_2),
          onPressed: _back,
        ),
        title: Text(
          l10n.authRecoverTitle,
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
                l10n.authWelcomeBack,
                style: AppTypography.sans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              SizedBox(height: context.spacing.space8),
              Text(
                l10n.authRecoverDescription,
                style: AppTypography.sans(
                  fontSize: 14,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
              SizedBox(height: context.spacing.space24),
              TextFormField(
                key: const Key('recover.email'),
                controller: _emailController,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: l10n.commonEmail,
                  hintText: l10n.commonEmailHintExample,
                ),
                validator: validateEmail,
                onFieldSubmitted: (_) => _send(),
              ),
              if (_serverError != null) ...[
                SizedBox(height: context.spacing.space12),
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
              SizedBox(height: context.spacing.space24),
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
                      : Text(l10n.authRecoverSubmit),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
