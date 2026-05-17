// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get offlineBannerMessage =>
      'You\'re offline — changes will sync later';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonOK => 'OK';

  @override
  String get currencyOMR => 'Omani rial';

  @override
  String get currencyAED => 'UAE dirham';

  @override
  String get currencySAR => 'Saudi riyal';

  @override
  String get currencyUSD => 'US dollar';

  @override
  String get currencyEUR => 'Euro';

  @override
  String get currencyGBP => 'British pound';

  @override
  String get currencyQAR => 'Qatari riyal';

  @override
  String get currencyKWD => 'Kuwaiti dinar';

  @override
  String get currencyBHD => 'Bahraini dinar';

  @override
  String get currencyJPY => 'Japanese yen';

  @override
  String get languageSheetTitle => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get currencySheetTitle => 'Currency';

  @override
  String get currencySheetSubtitle =>
      'Default for new trips. Existing trips keep their currency.';

  @override
  String get themeSheetTitle => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeSystemDescription => 'Follow device setting';

  @override
  String get themeLight => 'Light';

  @override
  String get themeLightDescription => 'Always light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeDarkDescription => 'Always dark';

  @override
  String get defaultSplitSheetTitle => 'Default split';

  @override
  String get defaultSplitSheetSubtitle =>
      'Applied to new expenses. You can still change the split per expense.';

  @override
  String get splitModeEqually => 'Equal';

  @override
  String get splitModeShares => 'Shares';

  @override
  String get splitModeExact => 'Exact amounts';

  @override
  String get splitModePercent => 'Percent';

  @override
  String get editNameTitle => 'What should we call you?';

  @override
  String get editNameHelper => 'This is how friends will see you in groups.';

  @override
  String get editNameFieldLabel => 'Display name';

  @override
  String get editNameFieldHint => 'Your name';

  @override
  String get editNameInitialsCaption => 'INITIALS SHOWN WHEN NO PHOTO';

  @override
  String get legalSheetTitle => 'Legal';

  @override
  String get legalTermsOfService => 'Terms of service';

  @override
  String get legalPrivacyPolicy => 'Privacy policy';

  @override
  String get legalDeleteMyData => 'Delete my data';

  @override
  String get qrSheetTitle => 'My QR';

  @override
  String get qrSemanticsLabel => 'Profile QR code';

  @override
  String get qrCopyHandle => 'Copy handle';

  @override
  String get qrHandleCopied => 'Handle copied';

  @override
  String get profileSectionPreferences => 'PREFERENCES';

  @override
  String get profileSectionAccount => 'ACCOUNT';

  @override
  String get profileSectionAbout => 'ABOUT';

  @override
  String get profileSectionDisplay => 'DISPLAY';

  @override
  String get profileSectionJourney => 'YOUR JOURNEY';

  @override
  String get profileStatsGroups => 'Groups';

  @override
  String get profileStatsEvents => 'Events';

  @override
  String get profileStatsSpent => 'Spent';

  @override
  String get profileStatsJourneysLabel => 'JOURNEYS';

  @override
  String get profileStatsGroupsLabel => 'GROUPS';

  @override
  String get profileStatsSpentLabel => 'SPENT';

  @override
  String get profileNotificationsSectionLabel => 'NOTIFICATIONS';

  @override
  String get profileNotificationsTitle => 'Push Notifications';

  @override
  String get profileNotificationsEnabled => 'Enabled';

  @override
  String get profileNotificationsDisabledHint => 'Enable in device Settings';

  @override
  String get profileNotificationsSubtitle => 'Activity & settles';

  @override
  String get profileAboutVersion => 'Version';

  @override
  String get profileAboutSendFeedback => 'Send Feedback';

  @override
  String get profileAboutSendFeedbackRow => 'Send feedback';

  @override
  String get profileAboutLicenses => 'Open-source Licenses';

  @override
  String profileAboutFallbackEmail(String email) {
    return 'Email: $email';
  }

  @override
  String get profileAboutHelpCenter => 'Help center';

  @override
  String get profileAboutTermsPrivacy => 'Terms & privacy';

  @override
  String get profileDisplayTheme => 'Theme';

  @override
  String get profileDisplayThemeSystemValue => 'System • Following device';

  @override
  String get profileDisplayThemeLightValue => 'Light';

  @override
  String get profileDisplayThemeDarkValue => 'Dark';

  @override
  String get profileSupportSectionLabel => 'SUPPORT';

  @override
  String get profileSupportCoffeeTile => 'Buy me a coffee';

  @override
  String get profileSupportPaypalFailed => 'Couldn\'t open PayPal';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileAnonymousTraveller => 'Anonymous traveller';

  @override
  String get profileSetYourName => 'Set your name';

  @override
  String get profileFinishRecovery => 'Finish account recovery';

  @override
  String get profileRecoverySubtitle =>
      'A recovery link is waiting. Enter the email it was sent to.';

  @override
  String get profilePreferencesNotifications => 'Notifications';

  @override
  String get profilePreferencesCurrency => 'Currency';

  @override
  String get profilePreferencesLanguage => 'Language';

  @override
  String get profilePreferencesDefaultSplit => 'Default split';

  @override
  String get profileAccountLinkedEmail => 'Linked email';

  @override
  String get profileAccountNotSet => 'Not set';

  @override
  String get profileAccountSignOut => 'Sign out of this device';

  @override
  String get profileAccountDelete => 'Delete account';

  @override
  String get profileAccountDeletePermanent => 'Permanent';

  @override
  String get profileStatsAllTime => 'all-time';

  @override
  String get profileStatsActive => 'active';

  @override
  String get profileStatsLifetime => 'lifetime';

  @override
  String get profileShareMessage =>
      'I\'m splitting trip expenses with Rihla. Give it a try.';

  @override
  String get profileSnackHandleCopied => 'Handle copied';

  @override
  String get profileSnackSignedOut => 'Signed out';

  @override
  String get profileSnackSignOutFailed => 'Couldn\'t sign out. Try again.';

  @override
  String get profileSnackOpenLinkFailed => 'Couldn\'t open link';

  @override
  String get profileSnackNoEmailApp => 'No email app available';

  @override
  String get profileDeletionOk => 'Account deleted.';

  @override
  String get profileDeletionNoUser => 'No active account to delete.';

  @override
  String get profileDeletionError => 'Couldn\'t delete the account. Try again.';
}
