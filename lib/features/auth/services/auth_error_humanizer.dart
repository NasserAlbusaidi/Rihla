import '../../../l10n/generated/app_localizations.dart';

/// User-facing message for a Firebase auth error code. Extracted from the
/// email-link bootstrap's `_humanize` (#439) so the boot-time recovery
/// outcome notice reuses the exact same wording.
///
/// Localized when [l10n] is supplied (#841 PR-3 — the email-link bootstrap
/// resolves it via `appMessengerKey.currentContext`, mirroring the #843
/// `recovery_outcome_notice_provider.dart` precedent). The EN literal switch
/// below is the fallback used both when [l10n] is omitted/unavailable AND by
/// `recovery_outcome_notice.dart`'s `surfaceRecoveryOutcome`, which stays
/// deliberately context-free (#839) and never supplies one.
String humanizeAuthErrorCode(String code, {AppLocalizations? l10n}) {
  if (l10n != null) {
    switch (code) {
      case 'invalid-action-code':
      case 'expired-action-code':
        return l10n.authEmailLinkErrorExpired;
      case 'invalid-email':
        return l10n.authEmailLinkErrorInvalidEmail;
      case 'user-disabled':
        return l10n.authEmailLinkErrorDisabled;
      case 'network-request-failed':
        return l10n.authEmailLinkErrorNetwork;
      case 'too-many-requests':
        return l10n.authEmailLinkErrorTooManyRequests;
      case 'email-already-in-use':
      case 'credential-already-in-use':
      case 'provider-already-linked':
        return l10n.authEmailLinkErrorAlreadyInUse;
      default:
        return l10n.authEmailLinkErrorGeneric(code);
    }
  }
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
