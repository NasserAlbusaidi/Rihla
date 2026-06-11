/// User-facing message for a Firebase auth error code. Extracted from the
/// email-link bootstrap's `_humanize` (#439) so the boot-time recovery
/// outcome notice reuses the exact same wording.
///
/// English-only on purpose — the whole bootstrap snackbar surface is
/// hardcoded English today; localizing it is tracked debt, not this fix.
String humanizeAuthErrorCode(String code) {
  switch (code) {
    case 'invalid-action-code':
    case 'expired-action-code':
      return 'This link has expired or was already used. Send a new one.';
    case 'invalid-email':
      return "That email doesn't look valid.";
    case 'user-disabled':
      return 'This account has been disabled.';
    case 'network-request-failed':
      return 'No connection. Try again when you\'re online.';
    case 'too-many-requests':
      return 'Too many attempts. Wait a few minutes and try again.';
    case 'email-already-in-use':
    case 'credential-already-in-use':
    case 'provider-already-linked':
      return 'This email is already linked to a Rihla account. '
          'Restore from that account instead.';
    default:
      return 'Something went wrong ($code). Please try again.';
  }
}
