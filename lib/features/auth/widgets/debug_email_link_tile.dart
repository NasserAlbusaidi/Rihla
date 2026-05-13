import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/config/firebase_config.dart';
import '../services/auth_email_link_config.dart';

/// Debug-only trigger for the P0 email-link round trip.
///
/// Renders only in [kDebugMode] builds. Provides a single text field +
/// "Send sign-in link" button that calls
/// [FirebaseAuth.sendSignInLinkToEmail] with the centralized action code
/// settings. Lets us verify the App Links / Universal Links plumbing end
/// to end before P3 builds the real Settings UI.
///
/// Deletion target: when P3 lands, delete this file and the import in
/// profile_screen.dart.
class DebugEmailLinkTile extends StatefulWidget {
  const DebugEmailLinkTile({super.key});

  @override
  State<DebugEmailLinkTile> createState() => _DebugEmailLinkTileState();
}

class _DebugEmailLinkTileState extends State<DebugEmailLinkTile> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _controller.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showSnack('Enter a valid email');
      return;
    }
    setState(() => _sending = true);
    try {
      await FirebaseConfig.auth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: AuthEmailLinkConfig.actionCodeSettings(),
      );
      FirebaseConfig.log('Debug: sent sign-in link to $email');
      if (mounted) _showSnack('Sent. Check $email on this device.');
    } on FirebaseAuthException catch (error, stack) {
      FirebaseConfig.log(
        'Debug: sendSignInLinkToEmail failed (${error.code})',
        error: error,
        stackTrace: stack,
      );
      if (mounted) _showSnack('Error: ${error.code} — ${error.message}');
    } finally {
      if (mounted) setState(() => _sending = false);
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
                    'Debug · Email-link P0 trigger',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Sends a Firebase sign-in link to the email below. Tap the '
                'link on this device; the bootstrap listener should log the '
                'credential URL (oobCode redacted).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                enabled: !_sending,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Test email address',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_sending ? 'Sending…' : 'Send sign-in link'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
