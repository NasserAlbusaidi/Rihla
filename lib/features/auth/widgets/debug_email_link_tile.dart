import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../providers/auth_email_link_bootstrap_provider.dart';
import '../providers/auth_provider.dart';

/// Debug-only tile that exercises the email-link link/recover round trip.
///
/// Renders only in [kDebugMode] builds. Three actions are exposed so we can
/// drive the flow on real hardware without the production Settings UI:
///
/// * **Send sign-in link** — calls [AuthRecoveryService.linkEmailToCurrentUser]
///   (persists the email to SharedPreferences and fires Firebase's
///   `sendSignInLinkToEmail`). Costs one slot of the Spark daily quota.
/// * **Save email (no send)** — calls [AuthRecoveryService.setPendingEmail]
///   only. Lets us prime SharedPreferences when an email link already exists
///   (e.g. it's sitting in Gmail) without burning more daily quota.
/// * **Complete pending link** — visible only when the bootstrap listener
///   stashed a URL in [pendingEmailLinkProvider] because no pending email
///   was available on receive. Calls
///   [AuthRecoveryService.completeEmailLink] with the typed email as an
///   override.
///
/// Deletion target: when P3 lands, this entire file goes away and the
/// production Settings UI takes over.
class DebugEmailLinkTile extends ConsumerStatefulWidget {
  const DebugEmailLinkTile({super.key});

  @override
  ConsumerState<DebugEmailLinkTile> createState() =>
      _DebugEmailLinkTileState();
}

class _DebugEmailLinkTileState extends ConsumerState<DebugEmailLinkTile> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Prefill from the persisted pending email if one exists. Wrapped in
    // try/catch so widget tests that mount the profile screen without
    // initializing Firebase (the service constructor reaches into
    // FirebaseAuth.instance) don't blow up here.
    try {
      final pending = ref.read(authRecoveryServiceProvider).readPendingEmail();
      if (pending != null) _controller.text = pending;
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validatedEmail() {
    final email = _controller.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showSnack('Enter a valid email');
      return null;
    }
    return email;
  }

  Future<void> _send() async {
    final email = _validatedEmail();
    if (email == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRecoveryServiceProvider).linkEmailToCurrentUser(email);
      if (mounted) _showSnack('Sent. Check $email on this device.');
    } on FirebaseAuthException catch (error, stack) {
      FirebaseConfig.log(
        'Debug: linkEmailToCurrentUser failed (${error.code})',
        error: error,
        stackTrace: stack,
      );
      if (mounted) _showSnack('Error: ${error.code} — ${error.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveOnly() async {
    final email = _validatedEmail();
    if (email == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRecoveryServiceProvider).setPendingEmail(email);
      if (mounted) _showSnack('Saved. Tap the email link to complete.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completePending(String link) async {
    final email = _validatedEmail();
    if (email == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authRecoveryServiceProvider)
          .completeEmailLink(link, overrideEmail: email);
      ref.read(pendingEmailLinkProvider.notifier).state = null;
      if (mounted) _showSnack('Linked.');
    } on FirebaseAuthException catch (error, stack) {
      FirebaseConfig.log(
        'Debug: completeEmailLink failed (${error.code})',
        error: error,
        stackTrace: stack,
      );
      if (mounted) _showSnack('Error: ${error.code} — ${error.message}');
    } catch (error, stack) {
      FirebaseConfig.log(
        'Debug: completeEmailLink failed',
        error: error,
        stackTrace: stack,
      );
      if (mounted) _showSnack('Error: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    final linkedEmail = ref.watch(linkedEmailProvider);
    final pendingLink = ref.watch(pendingEmailLinkProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        color: Colors.amber.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.amber.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bug_report, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Debug · Email-link recovery trigger',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _StatusLine(
                label: 'Linked to anon UID',
                value: linkedEmail ?? 'not linked',
                ok: linkedEmail != null,
              ),
              if (pendingLink != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Pending link captured — type the email below and tap '
                  '"Complete pending link" to attach it.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.deepOrange.shade700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Test email address',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              if (pendingLink != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _completePending(pendingLink),
                    icon: const Icon(Icons.link),
                    label: const Text('Complete pending link'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _saveOnly,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save email (no send)'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _send,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_busy ? 'Working…' : 'Send sign-in link'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.value,
    required this.ok,
  });
  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final color = ok ? Colors.green.shade700 : Colors.grey.shade700;
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: color,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
