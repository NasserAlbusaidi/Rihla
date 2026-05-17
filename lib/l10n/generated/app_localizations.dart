import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// Banner shown when device is offline; reassures user that pending writes will be sent on reconnect.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — changes will sync later'**
  String get offlineBannerMessage;

  /// Generic Cancel action label for dialogs and sheets.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Generic Save action label. Pre-added for PR2b/PR3 reuse; some PR2a consumers also wire it.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// Generic Delete action label. Pre-added for PR2b/PR3 reuse.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// Generic OK confirmation label. Pre-added for PR2b/PR3 reuse.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOK;

  /// Display name for the Omani Rial currency.
  ///
  /// In en, this message translates to:
  /// **'Omani rial'**
  String get currencyOMR;

  /// Display name for the United Arab Emirates Dirham.
  ///
  /// In en, this message translates to:
  /// **'UAE dirham'**
  String get currencyAED;

  /// Display name for the Saudi Riyal.
  ///
  /// In en, this message translates to:
  /// **'Saudi riyal'**
  String get currencySAR;

  /// Display name for the United States Dollar.
  ///
  /// In en, this message translates to:
  /// **'US dollar'**
  String get currencyUSD;

  /// Display name for the Euro.
  ///
  /// In en, this message translates to:
  /// **'Euro'**
  String get currencyEUR;

  /// Display name for the British Pound Sterling.
  ///
  /// In en, this message translates to:
  /// **'British pound'**
  String get currencyGBP;

  /// Display name for the Qatari Riyal. Pre-added for future picker expansion.
  ///
  /// In en, this message translates to:
  /// **'Qatari riyal'**
  String get currencyQAR;

  /// Display name for the Kuwaiti Dinar. Pre-added for future picker expansion.
  ///
  /// In en, this message translates to:
  /// **'Kuwaiti dinar'**
  String get currencyKWD;

  /// Display name for the Bahraini Dinar. Pre-added for future picker expansion.
  ///
  /// In en, this message translates to:
  /// **'Bahraini dinar'**
  String get currencyBHD;

  /// Display name for the Japanese Yen. Pre-added for future picker expansion.
  ///
  /// In en, this message translates to:
  /// **'Japanese yen'**
  String get currencyJPY;

  /// Title of the LanguagePickerSheet bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSheetTitle;

  /// Autonym for English; stays as 'English' in both locales (language picker option).
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Autonym for Arabic; stays as 'العربية' in both locales (language picker option).
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// Title of the CurrencyPickerSheet bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currencySheetTitle;

  /// Subtitle text under CurrencyPickerSheet title explaining the scope of the preference.
  ///
  /// In en, this message translates to:
  /// **'Default for new trips. Existing trips keep their currency.'**
  String get currencySheetSubtitle;

  /// Title of the ThemePickerSheet bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeSheetTitle;

  /// Theme picker option: follow the device theme setting.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// Subtitle under the System theme option.
  ///
  /// In en, this message translates to:
  /// **'Follow device setting'**
  String get themeSystemDescription;

  /// Theme picker option: always-light theme.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// Subtitle under the Light theme option.
  ///
  /// In en, this message translates to:
  /// **'Always light'**
  String get themeLightDescription;

  /// Theme picker option: always-dark theme.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// Subtitle under the Dark theme option.
  ///
  /// In en, this message translates to:
  /// **'Always dark'**
  String get themeDarkDescription;

  /// Title of the DefaultSplitPickerSheet bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Default split'**
  String get defaultSplitSheetTitle;

  /// Subtitle under DefaultSplitPickerSheet title explaining the scope of the preference.
  ///
  /// In en, this message translates to:
  /// **'Applied to new expenses. You can still change the split per expense.'**
  String get defaultSplitSheetSubtitle;

  /// SplitMode.equally display name (split bill equally between participants).
  ///
  /// In en, this message translates to:
  /// **'Equal'**
  String get splitModeEqually;

  /// SplitMode.shares display name (weighted shares per participant).
  ///
  /// In en, this message translates to:
  /// **'Shares'**
  String get splitModeShares;

  /// SplitMode.exact display name (exact monetary amount per participant).
  ///
  /// In en, this message translates to:
  /// **'Exact amounts'**
  String get splitModeExact;

  /// SplitMode.percent display name (percentage per participant).
  ///
  /// In en, this message translates to:
  /// **'Percent'**
  String get splitModePercent;

  /// Heading of the EditNameBottomSheet.
  ///
  /// In en, this message translates to:
  /// **'What should we call you?'**
  String get editNameTitle;

  /// Helper copy under the EditNameBottomSheet heading.
  ///
  /// In en, this message translates to:
  /// **'This is how friends will see you in groups.'**
  String get editNameHelper;

  /// Label for the display-name text field in EditNameBottomSheet.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get editNameFieldLabel;

  /// Placeholder hint for the display-name text field.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get editNameFieldHint;

  /// All-caps caption above the initials chip selector (English typographic flourish; Arabic renders natural-case).
  ///
  /// In en, this message translates to:
  /// **'INITIALS SHOWN WHEN NO PHOTO'**
  String get editNameInitialsCaption;

  /// Title of the LegalLinksSheet bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get legalSheetTitle;

  /// Legal sheet row that opens the Terms of Service page.
  ///
  /// In en, this message translates to:
  /// **'Terms of service'**
  String get legalTermsOfService;

  /// Legal sheet row that opens the Privacy Policy page.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get legalPrivacyPolicy;

  /// Legal sheet row that opens the data-deletion request page.
  ///
  /// In en, this message translates to:
  /// **'Delete my data'**
  String get legalDeleteMyData;

  /// Title of the profile QR bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'My QR'**
  String get qrSheetTitle;

  /// Accessibility semantics label describing the rendered QR image.
  ///
  /// In en, this message translates to:
  /// **'Profile QR code'**
  String get qrSemanticsLabel;

  /// Button label that copies the profile handle to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy handle'**
  String get qrCopyHandle;

  /// SnackBar shown after the profile handle is copied (alias of profileSnackHandleCopied — same text).
  ///
  /// In en, this message translates to:
  /// **'Handle copied'**
  String get qrHandleCopied;

  /// Section header above the Preferences card on the Profile screen. English stays uppercase (typographic flourish + mono letterSpacing); Arabic renders natural-case.
  ///
  /// In en, this message translates to:
  /// **'PREFERENCES'**
  String get profileSectionPreferences;

  /// Section header above the Account card on the Profile screen. English stays uppercase; Arabic renders natural-case.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT'**
  String get profileSectionAccount;

  /// Section header above the About card on the Profile screen, also reused by ProfileAboutSection widget. English stays uppercase; Arabic renders natural-case.
  ///
  /// In en, this message translates to:
  /// **'ABOUT'**
  String get profileSectionAbout;

  /// Section header for ProfileDisplaySection (theme tile). English stays uppercase; Arabic renders natural-case.
  ///
  /// In en, this message translates to:
  /// **'DISPLAY'**
  String get profileSectionDisplay;

  /// Section header for ProfileStatsSection (cross-group stats). English stays uppercase; Arabic renders natural-case.
  ///
  /// In en, this message translates to:
  /// **'YOUR JOURNEY'**
  String get profileSectionJourney;

  /// Stat card label (singular form) in ProfileStatsSection.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get profileStatsGroups;

  /// Stat card label (singular form) in ProfileStatsSection.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get profileStatsEvents;

  /// Stat card label (singular form) in ProfileStatsSection.
  ///
  /// In en, this message translates to:
  /// **'Spent'**
  String get profileStatsSpent;

  /// All-caps mono stat label in active _StatCard widget on the Profile screen. English stays uppercase; Arabic renders natural-case.
  ///
  /// In en, this message translates to:
  /// **'JOURNEYS'**
  String get profileStatsJourneysLabel;

  /// All-caps mono stat label in active _StatCard widget on the Profile screen. English stays uppercase; Arabic renders natural-case.
  ///
  /// In en, this message translates to:
  /// **'GROUPS'**
  String get profileStatsGroupsLabel;

  /// All-caps mono stat label in active _StatCard widget on the Profile screen. English stays uppercase; Arabic renders natural-case.
  ///
  /// In en, this message translates to:
  /// **'SPENT'**
  String get profileStatsSpentLabel;

  /// Section header for ProfileNotificationsSection widget AND row title 'Notifications' in active _NotificationPrefRow on Profile screen. English stays uppercase in the widget header; rendered as the row title in profile_screen via the same key.
  ///
  /// In en, this message translates to:
  /// **'NOTIFICATIONS'**
  String get profileNotificationsSectionLabel;

  /// Tile title in ProfileNotificationsSection widget (currently dead/not-wired).
  ///
  /// In en, this message translates to:
  /// **'Push Notifications'**
  String get profileNotificationsTitle;

  /// Pre-add for a future enabled-state status label. Not wired in PR2a.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get profileNotificationsEnabled;

  /// Subtitle shown when push notifications are blocked by OS permission. Used by both the active _NotificationPrefRow and ProfileNotificationsSection widgets.
  ///
  /// In en, this message translates to:
  /// **'Enable in device Settings'**
  String get profileNotificationsDisabledHint;

  /// Default subtitle on the Notifications row in active _NotificationPrefRow when notifications are not OS-blocked.
  ///
  /// In en, this message translates to:
  /// **'Activity & settles'**
  String get profileNotificationsSubtitle;

  /// About-section tile label showing the app version (ProfileAboutSection widget).
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get profileAboutVersion;

  /// About-section tile that opens a mailto: feedback link. Note: profile_screen.dart's About card uses the lowercase 'Send feedback' variant — see profileAboutSendFeedbackRow.
  ///
  /// In en, this message translates to:
  /// **'Send Feedback'**
  String get profileAboutSendFeedback;

  /// About-card row label in active profile_screen.dart _AboutCard.
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get profileAboutSendFeedbackRow;

  /// About-section tile that opens the open-source licenses dialog.
  ///
  /// In en, this message translates to:
  /// **'Open-source Licenses'**
  String get profileAboutLicenses;

  /// Fallback SnackBar shown when mailto: launch fails. The email value is a literal ASCII address; Unicode bidi handles RTL/LTR mixing without explicit marks.
  ///
  /// In en, this message translates to:
  /// **'Email: {email}'**
  String profileAboutFallbackEmail(String email);

  /// About-card row that opens the external help URL (active profile_screen.dart _AboutCard).
  ///
  /// In en, this message translates to:
  /// **'Help center'**
  String get profileAboutHelpCenter;

  /// About-card row that opens the LegalLinksSheet (active profile_screen.dart _AboutCard).
  ///
  /// In en, this message translates to:
  /// **'Terms & privacy'**
  String get profileAboutTermsPrivacy;

  /// Title of the theme tile in ProfileDisplaySection.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get profileDisplayTheme;

  /// Trailing label on the theme tile when the System theme is selected.
  ///
  /// In en, this message translates to:
  /// **'System • Following device'**
  String get profileDisplayThemeSystemValue;

  /// Trailing label on the theme tile when the Light theme is selected.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get profileDisplayThemeLightValue;

  /// Trailing label on the theme tile when the Dark theme is selected.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get profileDisplayThemeDarkValue;

  /// Section header for ProfileSupportSection widget. English stays uppercase; Arabic renders natural-case.
  ///
  /// In en, this message translates to:
  /// **'SUPPORT'**
  String get profileSupportSectionLabel;

  /// Tile label in ProfileSupportSection that opens the PayPal donate URL.
  ///
  /// In en, this message translates to:
  /// **'Buy me a coffee'**
  String get profileSupportCoffeeTile;

  /// SnackBar shown when the PayPal launch fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open PayPal'**
  String get profileSupportPaypalFailed;

  /// Top-bar title on the Profile screen.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// Tagline shown under the user's display name on the identity card.
  ///
  /// In en, this message translates to:
  /// **'Anonymous traveller'**
  String get profileAnonymousTraveller;

  /// Placeholder shown in place of the display name when the user has not yet set a name.
  ///
  /// In en, this message translates to:
  /// **'Set your name'**
  String get profileSetYourName;

  /// Title of the pending-recovery banner shown when a magic link is waiting to be completed.
  ///
  /// In en, this message translates to:
  /// **'Finish account recovery'**
  String get profileFinishRecovery;

  /// Subtitle under the pending-recovery banner explaining what to do next.
  ///
  /// In en, this message translates to:
  /// **'A recovery link is waiting. Enter the email it was sent to.'**
  String get profileRecoverySubtitle;

  /// Row label for the notifications toggle in the Preferences card (the live preferences-row label; the dead ProfileNotificationsSection widget uses profileNotificationsTitle = 'Push Notifications' instead).
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get profilePreferencesNotifications;

  /// Row label for the currency preference in the Preferences card.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get profilePreferencesCurrency;

  /// Row label for the language preference in the Preferences card.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get profilePreferencesLanguage;

  /// Row label for the default-split preference in the Preferences card.
  ///
  /// In en, this message translates to:
  /// **'Default split'**
  String get profilePreferencesDefaultSplit;

  /// Row label for the linked-email status in the Account card.
  ///
  /// In en, this message translates to:
  /// **'Linked email'**
  String get profileAccountLinkedEmail;

  /// Trailing text on the linked-email row when no email has been linked.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get profileAccountNotSet;

  /// Row label for signing out of the current device (visible when an email is linked).
  ///
  /// In en, this message translates to:
  /// **'Sign out of this device'**
  String get profileAccountSignOut;

  /// Row label for the destructive account-deletion action.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get profileAccountDelete;

  /// Trailing label on the Delete account row warning the action is permanent.
  ///
  /// In en, this message translates to:
  /// **'Permanent'**
  String get profileAccountDeletePermanent;

  /// Subtitle on the Journeys stat card.
  ///
  /// In en, this message translates to:
  /// **'all-time'**
  String get profileStatsAllTime;

  /// Subtitle on the Groups stat card.
  ///
  /// In en, this message translates to:
  /// **'active'**
  String get profileStatsActive;

  /// Subtitle on the Spent stat card.
  ///
  /// In en, this message translates to:
  /// **'lifetime'**
  String get profileStatsLifetime;

  /// Body of the Share.share() invocation when the user shares the app. The 'Rihla' brand subject stays English per Q5.
  ///
  /// In en, this message translates to:
  /// **'I\'m splitting trip expenses with Rihla. Give it a try.'**
  String get profileShareMessage;

  /// SnackBar shown after the user copies their handle from the identity chip.
  ///
  /// In en, this message translates to:
  /// **'Handle copied'**
  String get profileSnackHandleCopied;

  /// SnackBar shown after a successful sign-out.
  ///
  /// In en, this message translates to:
  /// **'Signed out'**
  String get profileSnackSignedOut;

  /// SnackBar shown when sign-out fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sign out. Try again.'**
  String get profileSnackSignOutFailed;

  /// SnackBar shown when launchUrl fails for an external URL (also reused by LegalLinksSheet for the same failure).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open link'**
  String get profileSnackOpenLinkFailed;

  /// SnackBar shown when the mailto: launch fails because no email client is available.
  ///
  /// In en, this message translates to:
  /// **'No email app available'**
  String get profileSnackNoEmailApp;

  /// SnackBar shown after a successful account deletion.
  ///
  /// In en, this message translates to:
  /// **'Account deleted.'**
  String get profileDeletionOk;

  /// SnackBar shown when deletion is attempted with no active user.
  ///
  /// In en, this message translates to:
  /// **'No active account to delete.'**
  String get profileDeletionNoUser;

  /// SnackBar shown when account deletion fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the account. Try again.'**
  String get profileDeletionError;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
