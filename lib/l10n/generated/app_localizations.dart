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

  /// Title of the DeleteAccountDialog confirming destructive account deletion.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get deleteAccountTitle;

  /// Body copy of the DeleteAccountDialog spelling out what deletion means.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your Rihla account. Your linked email (if any) will be released so it can be reused. Trips, expenses, and balances tied to your account become unreachable. There\'s no undo.'**
  String get deleteAccountContent;

  /// Destructive confirm button on the DeleteAccountDialog.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccountConfirm;

  /// Title of the SignOutConfirmDialog confirming local sign-out.
  ///
  /// In en, this message translates to:
  /// **'Sign out of this device?'**
  String get signOutTitle;

  /// First text run of the SignOutConfirmDialog content, ending just before the bold email address.
  ///
  /// In en, this message translates to:
  /// **'Your data stays in the cloud. To restore, enter '**
  String get signOutContentPrefix;

  /// Trailing text run of the SignOutConfirmDialog content, immediately after the bold email address.
  ///
  /// In en, this message translates to:
  /// **' on any device.'**
  String get signOutContentSuffix;

  /// Confirm button on the SignOutConfirmDialog.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOutConfirm;

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

  /// No description provided for @commonApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get commonApply;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonGoHome.
  ///
  /// In en, this message translates to:
  /// **'Go Home'**
  String get commonGoHome;

  /// No description provided for @commonSemanticBackspace.
  ///
  /// In en, this message translates to:
  /// **'Backspace'**
  String get commonSemanticBackspace;

  /// No description provided for @commonSemanticDecimalPoint.
  ///
  /// In en, this message translates to:
  /// **'Decimal point'**
  String get commonSemanticDecimalPoint;

  /// No description provided for @timelineToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get timelineToday;

  /// No description provided for @timelineYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get timelineYesterday;

  /// No description provided for @timelineRangeSeparator.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get timelineRangeSeparator;

  /// No description provided for @ledgerBucketFood.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get ledgerBucketFood;

  /// No description provided for @ledgerBucketLodging.
  ///
  /// In en, this message translates to:
  /// **'Lodging'**
  String get ledgerBucketLodging;

  /// No description provided for @ledgerBucketTransit.
  ///
  /// In en, this message translates to:
  /// **'Transit'**
  String get ledgerBucketTransit;

  /// No description provided for @ledgerBucketGroceries.
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get ledgerBucketGroceries;

  /// No description provided for @ledgerBucketActivities.
  ///
  /// In en, this message translates to:
  /// **'Activities'**
  String get ledgerBucketActivities;

  /// No description provided for @ledgerBucketOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get ledgerBucketOther;

  /// No description provided for @categoryFood.
  ///
  /// In en, this message translates to:
  /// **'Food & Dining'**
  String get categoryFood;

  /// No description provided for @categoryTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get categoryTransport;

  /// No description provided for @categoryAccommodation.
  ///
  /// In en, this message translates to:
  /// **'Accommodation'**
  String get categoryAccommodation;

  /// No description provided for @categoryActivities.
  ///
  /// In en, this message translates to:
  /// **'Activities'**
  String get categoryActivities;

  /// No description provided for @categoryShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get categoryShopping;

  /// No description provided for @categoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get categoryOther;

  /// No description provided for @ledgerBackTooltip.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get ledgerBackTooltip;

  /// No description provided for @ledgerSearchExpensesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search expenses'**
  String get ledgerSearchExpensesTooltip;

  /// No description provided for @ledgerEventSettingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Event settings'**
  String get ledgerEventSettingsTooltip;

  /// No description provided for @ledgerPeopleCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 PERSON} other{{count} PEOPLE}}'**
  String ledgerPeopleCount(int count);

  /// No description provided for @ledgerAllFilter.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get ledgerAllFilter;

  /// No description provided for @ledgerCategoriesAppear.
  ///
  /// In en, this message translates to:
  /// **'categories appear as you log them'**
  String get ledgerCategoriesAppear;

  /// No description provided for @ledgerNothingInCategoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing in this category'**
  String get ledgerNothingInCategoryTitle;

  /// No description provided for @ledgerNothingInCategoryMessage.
  ///
  /// In en, this message translates to:
  /// **'Try a different category, or switch back to All.'**
  String get ledgerNothingInCategoryMessage;

  /// No description provided for @ledgerEndOfLedger.
  ///
  /// In en, this message translates to:
  /// **'END OF LEDGER'**
  String get ledgerEndOfLedger;

  /// No description provided for @ledgerEmptyStateTitle.
  ///
  /// In en, this message translates to:
  /// **'An empty page, ready to be written.'**
  String get ledgerEmptyStateTitle;

  /// No description provided for @ledgerEmptyStateFirstExpenseBody.
  ///
  /// In en, this message translates to:
  /// **'The first OMR you log will set the trip total. We\'ll split it equally between everyone on the trip.'**
  String get ledgerEmptyStateFirstExpenseBody;

  /// No description provided for @ledgerCouldNotLoadEventTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load event'**
  String get ledgerCouldNotLoadEventTitle;

  /// No description provided for @ledgerCouldNotLoadLedgerTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load ledger'**
  String get ledgerCouldNotLoadLedgerTitle;

  /// No description provided for @ledgerEventNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Event not found'**
  String get ledgerEventNotFoundTitle;

  /// No description provided for @ledgerConnectionRetryMessage.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get ledgerConnectionRetryMessage;

  /// No description provided for @ledgerEventNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted, or the link is incorrect.'**
  String get ledgerEventNotFoundMessage;

  /// No description provided for @ledgerReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get ledgerReload;

  /// No description provided for @ledgerHeroPositivePrefix.
  ///
  /// In en, this message translates to:
  /// **'You\'re up'**
  String get ledgerHeroPositivePrefix;

  /// No description provided for @ledgerHeroPositiveTail.
  ///
  /// In en, this message translates to:
  /// **'across {count, plural, =1{1 person} other{{count} people}}.'**
  String ledgerHeroPositiveTail(int count);

  /// No description provided for @ledgerHeroNegativePrefix.
  ///
  /// In en, this message translates to:
  /// **'You owe'**
  String get ledgerHeroNegativePrefix;

  /// No description provided for @ledgerHeroNegativeTail.
  ///
  /// In en, this message translates to:
  /// **'to {count, plural, =1{1 person} other{{count} people}}.'**
  String ledgerHeroNegativeTail(int count);

  /// No description provided for @ledgerHeroEmptyPrefix.
  ///
  /// In en, this message translates to:
  /// **'Nothing logged yet'**
  String get ledgerHeroEmptyPrefix;

  /// No description provided for @ledgerHeroEmptyTail.
  ///
  /// In en, this message translates to:
  /// **'add the first expense and we\'ll start the math.'**
  String get ledgerHeroEmptyTail;

  /// No description provided for @ledgerAllSquare.
  ///
  /// In en, this message translates to:
  /// **'All square.'**
  String get ledgerAllSquare;

  /// No description provided for @ledgerSettledBadge.
  ///
  /// In en, this message translates to:
  /// **'SETTLED'**
  String get ledgerSettledBadge;

  /// No description provided for @ledgerTripTotal.
  ///
  /// In en, this message translates to:
  /// **'TRIP TOTAL'**
  String get ledgerTripTotal;

  /// No description provided for @ledgerExpenseCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 expense} other{{count} expenses}}'**
  String ledgerExpenseCount(int count);

  /// No description provided for @ledgerSettledCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 settled} other{{count} settled}}'**
  String ledgerSettledCount(int count);

  /// No description provided for @ledgerYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get ledgerYou;

  /// No description provided for @ledgerEven.
  ///
  /// In en, this message translates to:
  /// **'EVEN'**
  String get ledgerEven;

  /// No description provided for @ledgerMemberFallback.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get ledgerMemberFallback;

  /// No description provided for @ledgerSomeone.
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get ledgerSomeone;

  /// No description provided for @ledgerSomeoneLower.
  ///
  /// In en, this message translates to:
  /// **'someone'**
  String get ledgerSomeoneLower;

  /// No description provided for @ledgerUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get ledgerUnknown;

  /// No description provided for @ledgerExpenseFallback.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get ledgerExpenseFallback;

  /// No description provided for @ledgerSettlementFallback.
  ///
  /// In en, this message translates to:
  /// **'Settlement'**
  String get ledgerSettlementFallback;

  /// No description provided for @ledgerSettlementLabel.
  ///
  /// In en, this message translates to:
  /// **'SETTLEMENT'**
  String get ledgerSettlementLabel;

  /// No description provided for @ledgerPaidConnector.
  ///
  /// In en, this message translates to:
  /// **'paid'**
  String get ledgerPaidConnector;

  /// No description provided for @ledgerPaidBy.
  ///
  /// In en, this message translates to:
  /// **'Paid by {name}'**
  String ledgerPaidBy(Object name);

  /// No description provided for @ledgerSplitWays.
  ///
  /// In en, this message translates to:
  /// **'split {count, plural, =1{1 way} other{{count} ways}}'**
  String ledgerSplitWays(int count);

  /// No description provided for @ledgerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search expenses'**
  String get ledgerSearchHint;

  /// No description provided for @ledgerSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search expenses'**
  String get ledgerSearchTitle;

  /// No description provided for @ledgerSearchPromptMessage.
  ///
  /// In en, this message translates to:
  /// **'Type to find by description, category, payer, recipient or note.'**
  String get ledgerSearchPromptMessage;

  /// No description provided for @ledgerSearchNoMatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get ledgerSearchNoMatchesTitle;

  /// No description provided for @ledgerSearchNoMatchesMessage.
  ///
  /// In en, this message translates to:
  /// **'Nothing in this event matches \"{query}\".'**
  String ledgerSearchNoMatchesMessage(Object query);

  /// No description provided for @ledgerRecentExpenses.
  ///
  /// In en, this message translates to:
  /// **'RECENT EXPENSES'**
  String get ledgerRecentExpenses;

  /// No description provided for @ledgerRecordedHistory.
  ///
  /// In en, this message translates to:
  /// **'RECORDED HISTORY'**
  String get ledgerRecordedHistory;

  /// No description provided for @ledgerPaymentDue.
  ///
  /// In en, this message translates to:
  /// **'PAYMENT DUE'**
  String get ledgerPaymentDue;

  /// No description provided for @ledgerYouAreOwed.
  ///
  /// In en, this message translates to:
  /// **'YOU ARE OWED'**
  String get ledgerYouAreOwed;

  /// No description provided for @ledgerYouOwe.
  ///
  /// In en, this message translates to:
  /// **'YOU OWE'**
  String get ledgerYouOwe;

  /// No description provided for @ledgerTripTotalPending.
  ///
  /// In en, this message translates to:
  /// **'Trip Total Pending'**
  String get ledgerTripTotalPending;

  /// No description provided for @ledgerTotalPaidByYou.
  ///
  /// In en, this message translates to:
  /// **'Total Paid by You'**
  String get ledgerTotalPaidByYou;

  /// No description provided for @ledgerGeneralCategory.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get ledgerGeneralCategory;

  /// No description provided for @ledgerOwedToYou.
  ///
  /// In en, this message translates to:
  /// **'Owed to you {currency} {amount}'**
  String ledgerOwedToYou(Object currency, Object amount);

  /// No description provided for @ledgerYouOweAmount.
  ///
  /// In en, this message translates to:
  /// **'You owe {currency} {amount}'**
  String ledgerYouOweAmount(Object currency, Object amount);

  /// No description provided for @ledgerSettled.
  ///
  /// In en, this message translates to:
  /// **'Settled'**
  String get ledgerSettled;

  /// No description provided for @ledgerPeople.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 person} other{{count} people}}'**
  String ledgerPeople(int count);

  /// No description provided for @ledgerGroup.
  ///
  /// In en, this message translates to:
  /// **'group'**
  String get ledgerGroup;

  /// No description provided for @ledgerAddExpense.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get ledgerAddExpense;

  /// No description provided for @ledgerSettleUp.
  ///
  /// In en, this message translates to:
  /// **'Settle up'**
  String get ledgerSettleUp;

  /// No description provided for @editorTitleAddExpense.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get editorTitleAddExpense;

  /// No description provided for @editorTitleEditExpense.
  ///
  /// In en, this message translates to:
  /// **'Edit expense'**
  String get editorTitleEditExpense;

  /// No description provided for @editorTitleNewExpense.
  ///
  /// In en, this message translates to:
  /// **'New expense'**
  String get editorTitleNewExpense;

  /// No description provided for @editorActionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get editorActionAdd;

  /// No description provided for @editorActionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get editorActionSave;

  /// No description provided for @editorCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get editorCategory;

  /// No description provided for @editorPaidBy.
  ///
  /// In en, this message translates to:
  /// **'Paid by'**
  String get editorPaidBy;

  /// No description provided for @editorSplitBetween.
  ///
  /// In en, this message translates to:
  /// **'Split between'**
  String get editorSplitBetween;

  /// No description provided for @editorHow.
  ///
  /// In en, this message translates to:
  /// **'How'**
  String get editorHow;

  /// No description provided for @editorWhere.
  ///
  /// In en, this message translates to:
  /// **'Where'**
  String get editorWhere;

  /// No description provided for @editorCustomise.
  ///
  /// In en, this message translates to:
  /// **'Customise'**
  String get editorCustomise;

  /// No description provided for @editorAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'AMOUNT · {currency}'**
  String editorAmountLabel(Object currency);

  /// No description provided for @editorDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get editorDescriptionLabel;

  /// No description provided for @editorDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'What was it for?'**
  String get editorDescriptionHint;

  /// No description provided for @editorPleaseEnterValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid amount'**
  String get editorPleaseEnterValidAmount;

  /// No description provided for @editorAmountGreaterThanZero.
  ///
  /// In en, this message translates to:
  /// **'Amount must be greater than zero'**
  String get editorAmountGreaterThanZero;

  /// No description provided for @editorCouldNotIdentifyParticipant.
  ///
  /// In en, this message translates to:
  /// **'Could not identify your participant record.'**
  String get editorCouldNotIdentifyParticipant;

  /// No description provided for @editorFailedToAddExpense.
  ///
  /// In en, this message translates to:
  /// **'Failed to add expense: {error}'**
  String editorFailedToAddExpense(String error);

  /// No description provided for @editorFailedToUpdateExpense.
  ///
  /// In en, this message translates to:
  /// **'Failed to update expense: {error}'**
  String editorFailedToUpdateExpense(String error);

  /// No description provided for @editorDeleteExpenseTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete expense?'**
  String get editorDeleteExpenseTitle;

  /// No description provided for @editorDeleteExpenseBody.
  ///
  /// In en, this message translates to:
  /// **'Removing it updates everyone\'s balances for this event.'**
  String get editorDeleteExpenseBody;

  /// No description provided for @editorDeleteExpenseFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete expense: {error}'**
  String editorDeleteExpenseFailed(Object error);

  /// No description provided for @editorPickAtLeastTwoPeople.
  ///
  /// In en, this message translates to:
  /// **'Pick at least two people in \"Split between\" first.'**
  String get editorPickAtLeastTwoPeople;

  /// No description provided for @editorCouldNotLoadCategories.
  ///
  /// In en, this message translates to:
  /// **'Could not load categories.'**
  String get editorCouldNotLoadCategories;

  /// No description provided for @editorMemberFallback.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get editorMemberFallback;

  /// No description provided for @editorPaidRole.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get editorPaidRole;

  /// No description provided for @editorSelectedPayer.
  ///
  /// In en, this message translates to:
  /// **'Selected payer'**
  String get editorSelectedPayer;

  /// No description provided for @editorSelectedPaidFullAmount.
  ///
  /// In en, this message translates to:
  /// **'Selected · paid the full amount'**
  String get editorSelectedPaidFullAmount;

  /// No description provided for @editorEventDefault.
  ///
  /// In en, this message translates to:
  /// **'EVENT DEFAULT'**
  String get editorEventDefault;

  /// No description provided for @editorTapCustomiseSplit.
  ///
  /// In en, this message translates to:
  /// **'Tap Customise to pick who splits this.'**
  String get editorTapCustomiseSplit;

  /// No description provided for @editorSplitSummary.
  ///
  /// In en, this message translates to:
  /// **'{scope} · {count, plural, =1{1 way} other{{count} ways}}'**
  String editorSplitSummary(Object scope, int count);

  /// No description provided for @editorEachAmount.
  ///
  /// In en, this message translates to:
  /// **'{amount} each'**
  String editorEachAmount(Object amount);

  /// No description provided for @editorPickAtLeastTwoToSplit.
  ///
  /// In en, this message translates to:
  /// **'Pick at least two people to split.'**
  String get editorPickAtLeastTwoToSplit;

  /// No description provided for @editorSplitEvenly.
  ///
  /// In en, this message translates to:
  /// **'Split evenly across {count, plural, =1{1 way} other{{count} ways}}.'**
  String editorSplitEvenly(int count);

  /// No description provided for @editorWeightedByShares.
  ///
  /// In en, this message translates to:
  /// **'Weighted by shares.'**
  String get editorWeightedByShares;

  /// No description provided for @editorPerPersonAmounts.
  ///
  /// In en, this message translates to:
  /// **'Per-person amounts.'**
  String get editorPerPersonAmounts;

  /// No description provided for @editorPerPersonPercents.
  ///
  /// In en, this message translates to:
  /// **'Per-person percents.'**
  String get editorPerPersonPercents;

  /// No description provided for @editorEvent.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get editorEvent;

  /// No description provided for @editorDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get editorDate;

  /// No description provided for @editorDeleteThisExpense.
  ///
  /// In en, this message translates to:
  /// **'Delete this expense'**
  String get editorDeleteThisExpense;

  /// No description provided for @editorDeleteThisExpenseBody.
  ///
  /// In en, this message translates to:
  /// **'Removes for everyone in this event.'**
  String get editorDeleteThisExpenseBody;

  /// No description provided for @editorCustomiseSplit.
  ///
  /// In en, this message translates to:
  /// **'Customise split'**
  String get editorCustomiseSplit;

  /// No description provided for @editorScopeGlobal.
  ///
  /// In en, this message translates to:
  /// **'Equally'**
  String get editorScopeGlobal;

  /// No description provided for @editorScopeSubGroup.
  ///
  /// In en, this message translates to:
  /// **'Group split'**
  String get editorScopeSubGroup;

  /// No description provided for @editorScopeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get editorScopeCustom;

  /// No description provided for @editorScopePersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get editorScopePersonal;

  /// No description provided for @editorReceiptOptional.
  ///
  /// In en, this message translates to:
  /// **'RECEIPT (OPTIONAL)'**
  String get editorReceiptOptional;

  /// No description provided for @editorReceiptUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading receipt...'**
  String get editorReceiptUploading;

  /// No description provided for @editorReceiptAttached.
  ///
  /// In en, this message translates to:
  /// **'Receipt attached'**
  String get editorReceiptAttached;

  /// No description provided for @editorReceiptTapToChange.
  ///
  /// In en, this message translates to:
  /// **'Tap to change'**
  String get editorReceiptTapToChange;

  /// No description provided for @editorReceiptAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add a receipt photo'**
  String get editorReceiptAddPhoto;

  /// No description provided for @customSplitTitle.
  ///
  /// In en, this message translates to:
  /// **'Customise split'**
  String get customSplitTitle;

  /// No description provided for @customSplitCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get customSplitCancel;

  /// No description provided for @customSplitApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get customSplitApply;

  /// No description provided for @customSplitHow.
  ///
  /// In en, this message translates to:
  /// **'Split how?'**
  String get customSplitHow;

  /// No description provided for @customSplitTotal.
  ///
  /// In en, this message translates to:
  /// **'TOTAL'**
  String get customSplitTotal;

  /// No description provided for @customSplitModeEqually.
  ///
  /// In en, this message translates to:
  /// **'Equally'**
  String get customSplitModeEqually;

  /// No description provided for @customSplitModeShares.
  ///
  /// In en, this message translates to:
  /// **'Shares'**
  String get customSplitModeShares;

  /// No description provided for @customSplitModeExact.
  ///
  /// In en, this message translates to:
  /// **'Exact'**
  String get customSplitModeExact;

  /// No description provided for @customSplitModePercent.
  ///
  /// In en, this message translates to:
  /// **'Percent'**
  String get customSplitModePercent;

  /// No description provided for @categoryPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s this for?'**
  String get categoryPickerTitle;

  /// No description provided for @categoryPickerCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load categories.'**
  String get categoryPickerCouldNotLoad;

  /// No description provided for @categoryPickerRestaurantsBarsCafes.
  ///
  /// In en, this message translates to:
  /// **'Restaurants, bars, cafes'**
  String get categoryPickerRestaurantsBarsCafes;

  /// No description provided for @categoryPickerHotelsRentals.
  ///
  /// In en, this message translates to:
  /// **'Hotels, rentals'**
  String get categoryPickerHotelsRentals;

  /// No description provided for @categoryPickerTaxiTrainFuel.
  ///
  /// In en, this message translates to:
  /// **'Taxi, train, fuel'**
  String get categoryPickerTaxiTrainFuel;

  /// No description provided for @categoryPickerMarketsSupplies.
  ///
  /// In en, this message translates to:
  /// **'Markets, supplies'**
  String get categoryPickerMarketsSupplies;

  /// No description provided for @categoryPickerToursTickets.
  ///
  /// In en, this message translates to:
  /// **'Tours, tickets'**
  String get categoryPickerToursTickets;

  /// No description provided for @categoryPickerPetrolCharging.
  ///
  /// In en, this message translates to:
  /// **'Petrol, charging'**
  String get categoryPickerPetrolCharging;

  /// No description provided for @categoryPickerEquipmentSupplies.
  ///
  /// In en, this message translates to:
  /// **'Equipment, supplies'**
  String get categoryPickerEquipmentSupplies;

  /// No description provided for @categoryPickerAnythingElse.
  ///
  /// In en, this message translates to:
  /// **'Anything else'**
  String get categoryPickerAnythingElse;

  /// No description provided for @settleUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Settle Up'**
  String get settleUpTitle;

  /// No description provided for @settleUpEventMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'This event no longer exists'**
  String get settleUpEventMissingTitle;

  /// No description provided for @settleUpEventMissingMessage.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted. Tap below to go back to your groups.'**
  String get settleUpEventMissingMessage;

  /// No description provided for @settleUpCouldNotLoadBalances.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load balances.'**
  String get settleUpCouldNotLoadBalances;

  /// No description provided for @settleUpAmountGreaterThanZero.
  ///
  /// In en, this message translates to:
  /// **'Amount must be greater than zero'**
  String get settleUpAmountGreaterThanZero;

  /// No description provided for @settleUpAmountExceedsOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Amount cannot exceed the outstanding balance of {amount}'**
  String settleUpAmountExceedsOutstanding(Object amount);

  /// No description provided for @settleUpRecorded.
  ///
  /// In en, this message translates to:
  /// **'Settlement recorded.'**
  String get settleUpRecorded;

  /// No description provided for @settleUpRecordFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t record settlement. Check your connection and try again.'**
  String get settleUpRecordFailed;

  /// No description provided for @settleUpEveryoneEvenHeadline.
  ///
  /// In en, this message translates to:
  /// **'Everyone\'s even.'**
  String get settleUpEveryoneEvenHeadline;

  /// No description provided for @settleUpTransfersHeadline.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One transfer,\neveryone\'s even.} other{{count} transfers,\neveryone\'s even.}}'**
  String settleUpTransfersHeadline(int count);

  /// No description provided for @settleUpNoOptimizedPayments.
  ///
  /// In en, this message translates to:
  /// **'No optimized payments are needed across {subjectName}.'**
  String settleUpNoOptimizedPayments(Object subjectName);

  /// No description provided for @settleUpOptimizedPayments.
  ///
  /// In en, this message translates to:
  /// **'Optimized to minimise the number of payments across {subjectName}.'**
  String settleUpOptimizedPayments(Object subjectName);

  /// No description provided for @settleUpSummaryTransfers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transfer} other{{count} transfers}}'**
  String settleUpSummaryTransfers(int count);

  /// No description provided for @settleUpSummaryTotal.
  ///
  /// In en, this message translates to:
  /// **'{amount} total'**
  String settleUpSummaryTotal(Object amount);

  /// No description provided for @settleUpEachPersonNet.
  ///
  /// In en, this message translates to:
  /// **'Each person\'s net'**
  String get settleUpEachPersonNet;

  /// No description provided for @settleUpPaymentHistory.
  ///
  /// In en, this message translates to:
  /// **'Payment history'**
  String get settleUpPaymentHistory;

  /// No description provided for @settleUpUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get settleUpUnknown;

  /// No description provided for @settleUpPaidConnector.
  ///
  /// In en, this message translates to:
  /// **'paid'**
  String get settleUpPaidConnector;

  /// No description provided for @settleUpMarkThisPaidTitle.
  ///
  /// In en, this message translates to:
  /// **'Mark this paid?'**
  String get settleUpMarkThisPaidTitle;

  /// No description provided for @settleUpMarkThisPaidBody.
  ///
  /// In en, this message translates to:
  /// **'We\'ll close out the balance between {fromName} and {toName}.'**
  String settleUpMarkThisPaidBody(Object fromName, Object toName);

  /// No description provided for @settleUpNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Add a note (optional)'**
  String get settleUpNoteHint;

  /// No description provided for @settleUpNotifyToConfirm.
  ///
  /// In en, this message translates to:
  /// **'{name} will be notified to confirm.'**
  String settleUpNotifyToConfirm(Object name);

  /// No description provided for @settleUpNotYet.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get settleUpNotYet;

  /// No description provided for @settleUpMarkPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark paid'**
  String get settleUpMarkPaid;

  /// No description provided for @settleUpPays.
  ///
  /// In en, this message translates to:
  /// **'{fromName} pays {toName}'**
  String settleUpPays(Object fromName, Object toName);

  /// No description provided for @settleUpHideAmountEditor.
  ///
  /// In en, this message translates to:
  /// **'Hide amount editor'**
  String get settleUpHideAmountEditor;

  /// No description provided for @settleUpTapToEditAmount.
  ///
  /// In en, this message translates to:
  /// **'Tap to edit amount'**
  String get settleUpTapToEditAmount;

  /// No description provided for @settleUpAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount ({currency})'**
  String settleUpAmountLabel(Object currency);

  /// No description provided for @settleUpSuggestedAmount.
  ///
  /// In en, this message translates to:
  /// **'Suggested: {amount}'**
  String settleUpSuggestedAmount(Object amount);

  /// No description provided for @settleUpMethodCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get settleUpMethodCash;

  /// No description provided for @settleUpMethodBank.
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get settleUpMethodBank;

  /// No description provided for @settleUpMethodOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get settleUpMethodOther;

  /// No description provided for @settleUpAllSettledTitle.
  ///
  /// In en, this message translates to:
  /// **'All settled up'**
  String get settleUpAllSettledTitle;

  /// No description provided for @settleUpAllSettledMessage.
  ///
  /// In en, this message translates to:
  /// **'Everyone is square. No outstanding amounts.'**
  String get settleUpAllSettledMessage;

  /// No description provided for @settleUpYouOwe.
  ///
  /// In en, this message translates to:
  /// **'You owe {name}'**
  String settleUpYouOwe(Object name);

  /// No description provided for @settleUpOwesYou.
  ///
  /// In en, this message translates to:
  /// **'{name} owes you'**
  String settleUpOwesYou(Object name);

  /// No description provided for @settleUpOwes.
  ///
  /// In en, this message translates to:
  /// **'{fromName} owes {toName}'**
  String settleUpOwes(Object fromName, Object toName);

  /// No description provided for @expenseSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Expense Saved'**
  String get expenseSuccessTitle;

  /// No description provided for @expenseSuccessSyncedToCloud.
  ///
  /// In en, this message translates to:
  /// **'SYNCED TO CLOUD'**
  String get expenseSuccessSyncedToCloud;

  /// No description provided for @expenseSuccessDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get expenseSuccessDone;

  /// No description provided for @expenseSuccessAddAnother.
  ///
  /// In en, this message translates to:
  /// **'Add Another'**
  String get expenseSuccessAddAnother;

  /// No description provided for @expenseSuccessTotalAmount.
  ///
  /// In en, this message translates to:
  /// **'TOTAL AMOUNT'**
  String get expenseSuccessTotalAmount;

  /// No description provided for @expenseSuccessCategory.
  ///
  /// In en, this message translates to:
  /// **'CATEGORY'**
  String get expenseSuccessCategory;
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
