/// Outbound URLs and contact addresses surfaced from the UI.
///
/// These constants centralise every link the app opens externally (help,
/// legal, feedback). Legal/help pages live on `rihla-safar.web.app`,
/// the canonical Firebase Hosting domain (the bare `rihla.app` domain was
/// dropped in #130 — do not reintroduce it).
class AppLinks {
  const AppLinks._();

  static const String helpUrl = 'https://rihla-safar.web.app/help';
  static const String termsUrl = 'https://rihla-safar.web.app/terms';
  static const String privacyUrl = 'https://rihla-safar.web.app/privacy';
  static const String deleteDataUrl = 'https://rihla-safar.web.app/delete-data';
  static const String inviteLinkHost = 'rihla-safar.web.app';

  static Uri inviteUrl(String inviteCode) {
    return Uri.https(
      inviteLinkHost,
      '/join/${inviteCode.trim().toUpperCase()}',
    );
  }

  static const String feedbackEmail = 'nasserbusaidi@gmail.com';

}
