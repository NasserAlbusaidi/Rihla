/// Outbound URLs and contact addresses surfaced from the UI.
///
/// These constants centralise every link the app opens externally (help,
/// legal, feedback, tipping). The `rihla.app` host is a stub for the
/// pre-launch period — pages need to exist before alpha release.
class AppLinks {
  const AppLinks._();

  static const String helpUrl = 'https://rihla.app/help';
  static const String termsUrl = 'https://rihla.app/terms';
  static const String privacyUrl = 'https://rihla.app/privacy';

  static const String feedbackEmail = 'nasserbusaidi@gmail.com';

  /// PayPal donate URL targeting the linked email account. USD because
  /// PayPal does not support OMR as a transaction currency.
  static const String paypalUrl =
      'https://www.paypal.com/donate/?business=nalbusaidi5@gmail.com'
      '&item_name=Buy+Nasser+a+coffee&currency_code=USD';
}
