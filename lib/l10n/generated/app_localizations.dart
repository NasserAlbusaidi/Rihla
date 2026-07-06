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

  /// Transient banner shown after a write is saved locally while offline; reassures the user it will sync to the server on reconnect (#357).
  ///
  /// In en, this message translates to:
  /// **'Saved — will sync'**
  String get bannerSavedWillSync;

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

  /// No description provided for @createGroupCurrencyHint.
  ///
  /// In en, this message translates to:
  /// **'This group\'s currency. It can\'t be changed later.'**
  String get createGroupCurrencyHint;

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

  /// Caption beside the static RAvatar preview in EditNameBottomSheet, replacing the removed fake initials-style selector (#818 Wave 4).
  ///
  /// In en, this message translates to:
  /// **'How you\'ll appear in groups'**
  String get editNamePreviewCaption;

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

  /// Section header above the Preferences card on the Profile screen. English stays uppercase (typographic flourish + mono letterSpacing); Arabic renders natural-case.
  ///
  /// In en, this message translates to:
  /// **'PREFERENCES'**
  String get profileSectionPreferences;

  /// Section header above the account credential/recovery card on the Profile screen. #807 renamed it from BACKUP & RECOVERY: the card also holds Sign out, which is an account action, not a recovery one. English stays uppercase; Arabic renders natural-case.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT'**
  String get profileSectionAccount;

  /// Section header above the danger-zone card (delete account) on the Profile screen (#487 bullet 3). English stays uppercase; Arabic renders natural-case.
  ///
  /// In en, this message translates to:
  /// **'DANGER'**
  String get profileSectionDanger;

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

  /// Subtitle on the Notifications row when registration failed (NotificationStatus.error): the user is opted-in but the token write threw, so nothing is delivered. Tapping retries (#482).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t register — tap to retry'**
  String get profileNotificationsErrorHint;

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

  /// No description provided for @profileBackupStatusNotBackedUp.
  ///
  /// In en, this message translates to:
  /// **'Not backed up'**
  String get profileBackupStatusNotBackedUp;

  /// No description provided for @profileBackupStatusBackedUp.
  ///
  /// In en, this message translates to:
  /// **'Backed up'**
  String get profileBackupStatusBackedUp;

  /// No description provided for @profileBackupCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Back up this account'**
  String get profileBackupCardTitle;

  /// No description provided for @profileBackupCardBody.
  ///
  /// In en, this message translates to:
  /// **'Your trips live only on this phone. Link Google so you never lose them.'**
  String get profileBackupCardBody;

  /// Placeholder shown in place of the display name when the user has not yet set a name.
  ///
  /// In en, this message translates to:
  /// **'Set your name'**
  String get profileSetYourName;

  /// Shown on the identity chip in place of an @handle when the user has not set a name. Deliberately not @-prefixed so it does not read as a cut-off email (#163).
  ///
  /// In en, this message translates to:
  /// **'no name yet'**
  String get profileHandlePlaceholder;

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

  /// Title of the DeleteAccountDialog when the live session is an anonymous guest shell (#469).
  ///
  /// In en, this message translates to:
  /// **'Delete this guest session?'**
  String get deleteGuestSessionTitle;

  /// Body copy of the DeleteAccountDialog for an anonymous session, clarifying a linked durable account is not affected (#469).
  ///
  /// In en, this message translates to:
  /// **'This deletes only this guest session on this device. Any Google or email account you\'ve linked is separate and is NOT deleted unless you sign in to it first. There\'s no undo.'**
  String get deleteGuestSessionContent;

  /// Destructive confirm button on the DeleteAccountDialog for an anonymous guest session (#469).
  ///
  /// In en, this message translates to:
  /// **'Delete guest data'**
  String get deleteGuestSessionConfirm;

  /// Title of the DurableShellDeleteDialog shown when an anonymous session tries to delete but a durable account was established on this device (#469 prevention).
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get durableShellDeleteTitle;

  /// Body copy of the DurableShellDeleteDialog explaining the anon-shell delete would not remove the durable account (#469 prevention).
  ///
  /// In en, this message translates to:
  /// **'A saved account is set up on this device. Deleting now removes only this guest session — your saved account and its data stay. To delete your saved account, sign in to it first using the account options on this screen.'**
  String get durableShellDeleteContent;

  /// Primary button on the DurableShellDeleteDialog that dismisses so the user can sign in to their durable account first (#469 prevention).
  ///
  /// In en, this message translates to:
  /// **'Sign in to my account'**
  String get durableShellDeleteSignIn;

  /// Secondary destructive button on the DurableShellDeleteDialog that proceeds with deleting only the guest shell (#469 prevention).
  ///
  /// In en, this message translates to:
  /// **'Delete just this guest session'**
  String get durableShellDeleteGuest;

  /// Cancel button on the DurableShellDeleteDialog (#469 prevention).
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get durableShellDeleteCancel;

  /// Title of the dialog shown when account deletion partially completed and can be retried.
  ///
  /// In en, this message translates to:
  /// **'Deletion didn\'t finish'**
  String get deleteAccountRetryTitle;

  /// Body copy explaining a partial account deletion that converges on retry.
  ///
  /// In en, this message translates to:
  /// **'Some of your account data was removed, but the deletion didn\'t finish. Your account is still signed in. Retrying will complete it.'**
  String get deleteAccountRetryContent;

  /// Title of the SignOutConfirmDialog confirming local sign-out.
  ///
  /// In en, this message translates to:
  /// **'Sign out of this device?'**
  String get signOutTitle;

  /// Sign-out dialog body for a Google-credentialed user with no linked email (#428): recovery is via Google sign-in, not an email link.
  ///
  /// In en, this message translates to:
  /// **'Your data stays in the cloud. To restore, sign back in with the same Google account.'**
  String get signOutContentGoogle;

  /// Label of the Account-card row showing the linked Google identity (#428).
  ///
  /// In en, this message translates to:
  /// **'Google account'**
  String get profileAccountGoogle;

  /// Trailing text on the Google-account row when the provider entry carries no email (#428).
  ///
  /// In en, this message translates to:
  /// **'Linked'**
  String get profileAccountGoogleLinked;

  /// Account-card row for an anonymous user: opens the durable-credential sheet to link Google voluntarily (#428).
  ///
  /// In en, this message translates to:
  /// **'Link Google account'**
  String get profileAccountLinkGoogle;

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

  /// No description provided for @profileStatsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your stats'**
  String get profileStatsLoadFailed;

  /// Overflow indicator on the Profile Spent stat when lifetime spend spans more than two currencies; shows how many additional currency lines are hidden. Digit-only; no FX, currencies never summed.
  ///
  /// In en, this message translates to:
  /// **'+{count}'**
  String profileStatsSpentMore(int count);

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
  /// **'Food'**
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

  /// No description provided for @categoryGroceries.
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get categoryGroceries;

  /// No description provided for @categoryDrinks.
  ///
  /// In en, this message translates to:
  /// **'Drinks'**
  String get categoryDrinks;

  /// No description provided for @categoryFuel.
  ///
  /// In en, this message translates to:
  /// **'Fuel'**
  String get categoryFuel;

  /// No description provided for @categoryFees.
  ///
  /// In en, this message translates to:
  /// **'Fees'**
  String get categoryFees;

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

  /// No description provided for @ledgerActivityTooltip.
  ///
  /// In en, this message translates to:
  /// **'Activity log'**
  String get ledgerActivityTooltip;

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

  /// #807 — caption under the category strip while a category filter is active and the event has settlement rows (they're structurally category-less, so the filter hides them all).
  ///
  /// In en, this message translates to:
  /// **'Settlements aren\'t categorized, so they\'re hidden while filtering.'**
  String get ledgerSettlementsHiddenByCategory;

  /// No description provided for @ledgerClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get ledgerClearFilters;

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
  /// **'The first {currency} you log will set the trip total. We\'ll split it equally between everyone on the trip.'**
  String ledgerEmptyStateFirstExpenseBody(Object currency);

  /// No description provided for @ledgerEmptyFirstExpenseCamping.
  ///
  /// In en, this message translates to:
  /// **'The first {currency} you log will set the camping total. We\'ll split it equally between everyone camping.'**
  String ledgerEmptyFirstExpenseCamping(Object currency);

  /// No description provided for @ledgerEmptyFirstExpenseOuting.
  ///
  /// In en, this message translates to:
  /// **'The first {currency} you log will set the outing total. We\'ll split it equally between everyone on the outing.'**
  String ledgerEmptyFirstExpenseOuting(Object currency);

  /// No description provided for @ledgerEmptyFirstExpenseEvent.
  ///
  /// In en, this message translates to:
  /// **'The first {currency} you log will set the event total. We\'ll split it equally between everyone in the group.'**
  String ledgerEmptyFirstExpenseEvent(Object currency);

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

  /// No description provided for @editorCategoryPrompt.
  ///
  /// In en, this message translates to:
  /// **'What was this for?'**
  String get editorCategoryPrompt;

  /// No description provided for @editorCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get editorCategory;

  /// Validation shown when the user tries to save an expense without picking a category — category is mandatory at creation (#204).
  ///
  /// In en, this message translates to:
  /// **'Choose a category'**
  String get editorCategoryRequired;

  /// No description provided for @editorPaidBy.
  ///
  /// In en, this message translates to:
  /// **'Paid by'**
  String get editorPaidBy;

  /// No description provided for @editorChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get editorChange;

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

  /// No description provided for @editorAmountTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Amount is too large.'**
  String get editorAmountTooLarge;

  /// No description provided for @editorExactSplitOutOfSync.
  ///
  /// In en, this message translates to:
  /// **'The exact amounts no longer add up to the total. Reopen the split to update them.'**
  String get editorExactSplitOutOfSync;

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

  /// No description provided for @editorProvenanceAdded.
  ///
  /// In en, this message translates to:
  /// **'Added by {name}'**
  String editorProvenanceAdded(Object name);

  /// No description provided for @editorProvenanceAddedEdited.
  ///
  /// In en, this message translates to:
  /// **'Added by {creator} · edited by {editor}'**
  String editorProvenanceAddedEdited(Object creator, Object editor);

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

  /// Soft, non-blocking warning shown in the add-expense form when the picked currency differs from the event's dominant (most-frequent) currency — a fat-finger guard, not a hard block (#382 PR-6). {selected} is the picked ISO code, {dominant} the event's most-used ISO code.
  ///
  /// In en, this message translates to:
  /// **'This expense is in {selected}, but this event mostly uses {dominant}.'**
  String editorCurrencyMismatch(Object selected, Object dominant);

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

  /// No description provided for @editorAmountsVary.
  ///
  /// In en, this message translates to:
  /// **'Amounts vary per person.'**
  String get editorAmountsVary;

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

  /// Add-mode-only Where card title naming the target event, paired with the trailing 'change' button (#900).
  ///
  /// In en, this message translates to:
  /// **'Adding to {eventName}'**
  String editorAddingToEvent(String eventName);

  /// Trailing tap target next to editorAddingToEvent that opens the target picker to switch which event the expense is added to (#900).
  ///
  /// In en, this message translates to:
  /// **'change'**
  String get editorChangeDestination;

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

  /// No description provided for @editorDiscardAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard this expense?'**
  String get editorDiscardAddTitle;

  /// No description provided for @editorDiscardEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard your changes?'**
  String get editorDiscardEditTitle;

  /// No description provided for @editorDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll lose what you\'ve entered.'**
  String get editorDiscardBody;

  /// No description provided for @editorDiscardKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get editorDiscardKeepEditing;

  /// No description provided for @editorDiscardConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get editorDiscardConfirm;

  /// No description provided for @editorCustomiseSplit.
  ///
  /// In en, this message translates to:
  /// **'Customise split'**
  String get editorCustomiseSplit;

  /// No description provided for @editorSelectParticipants.
  ///
  /// In en, this message translates to:
  /// **'SELECT PARTICIPANTS'**
  String get editorSelectParticipants;

  /// No description provided for @editorSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected} other{{count} selected}}'**
  String editorSelectedCount(int count);

  /// No description provided for @editorUnableToLoadParticipants.
  ///
  /// In en, this message translates to:
  /// **'Unable to load participants'**
  String get editorUnableToLoadParticipants;

  /// No description provided for @editorNoOtherParticipants.
  ///
  /// In en, this message translates to:
  /// **'No other participants to select'**
  String get editorNoOtherParticipants;

  /// No description provided for @editorUnknownParticipant.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get editorUnknownParticipant;

  /// Caption under a placeholder (shadow) member's name in participant pickers, shown before they've joined the group themselves.
  ///
  /// In en, this message translates to:
  /// **'Hasn\'t joined yet'**
  String get editorShadowProfile;

  /// No description provided for @editorPaidByLabel.
  ///
  /// In en, this message translates to:
  /// **'PAID BY'**
  String get editorPaidByLabel;

  /// No description provided for @editorParticipantMe.
  ///
  /// In en, this message translates to:
  /// **'{name} (Me)'**
  String editorParticipantMe(Object name);

  /// No description provided for @editorCouldNotLoadExpenseTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load expense'**
  String get editorCouldNotLoadExpenseTitle;

  /// No description provided for @editorCouldNotLoadExpenseMessage.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again in a moment.'**
  String get editorCouldNotLoadExpenseMessage;

  /// No description provided for @editorExpenseNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Expense not found'**
  String get editorExpenseNotFoundTitle;

  /// No description provided for @editorExpenseNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'This expense may have been deleted.'**
  String get editorExpenseNotFoundMessage;

  /// No description provided for @editorViewOnlyTitle.
  ///
  /// In en, this message translates to:
  /// **'View only'**
  String get editorViewOnlyTitle;

  /// No description provided for @editorViewOnlyMessage.
  ///
  /// In en, this message translates to:
  /// **'Only people in this event can edit expenses.'**
  String get editorViewOnlyMessage;

  /// No description provided for @editorExpenseDeleted.
  ///
  /// In en, this message translates to:
  /// **'Expense deleted'**
  String get editorExpenseDeleted;

  /// No description provided for @editorScopeGlobal.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get editorScopeGlobal;

  /// No description provided for @editorScopeSubGroup.
  ///
  /// In en, this message translates to:
  /// **'Group split'**
  String get editorScopeSubGroup;

  /// No description provided for @editorScopeCustom.
  ///
  /// In en, this message translates to:
  /// **'Some people'**
  String get editorScopeCustom;

  /// No description provided for @editorScopePersonal.
  ///
  /// In en, this message translates to:
  /// **'Just me'**
  String get editorScopePersonal;

  /// No description provided for @editorSplit.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get editorSplit;

  /// No description provided for @editorWhoSplits.
  ///
  /// In en, this message translates to:
  /// **'Who splits'**
  String get editorWhoSplits;

  /// No description provided for @editorSplitModeExactShort.
  ///
  /// In en, this message translates to:
  /// **'Exact'**
  String get editorSplitModeExactShort;

  /// No description provided for @editorSplitModePercentShort.
  ///
  /// In en, this message translates to:
  /// **'%'**
  String get editorSplitModePercentShort;

  /// No description provided for @editorSplitAddsUpTo.
  ///
  /// In en, this message translates to:
  /// **'Adds up to {amount}'**
  String editorSplitAddsUpTo(String amount);

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

  /// No description provided for @editorSplitItemized.
  ///
  /// In en, this message translates to:
  /// **'Itemized'**
  String get editorSplitItemized;

  /// One-line helper under the split-mode chips explaining the Equal mode.
  ///
  /// In en, this message translates to:
  /// **'Everyone pays the same.'**
  String get splitModeHelpEqually;

  /// One-line helper under the split-mode chips explaining the Shares mode.
  ///
  /// In en, this message translates to:
  /// **'Weight who owes more — e.g. couples or big eaters.'**
  String get splitModeHelpShares;

  /// One-line helper under the split-mode chips explaining the Exact mode.
  ///
  /// In en, this message translates to:
  /// **'Type each person\'s exact share.'**
  String get splitModeHelpExact;

  /// One-line helper under the split-mode chips explaining the Percent mode.
  ///
  /// In en, this message translates to:
  /// **'Split by percentage of the total.'**
  String get splitModeHelpPercent;

  /// One-line helper under the split-mode chips explaining the Itemized mode.
  ///
  /// In en, this message translates to:
  /// **'Add each receipt line and tick who ordered it.'**
  String get splitModeHelpItemized;

  /// No description provided for @itemizedItemsHeader.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get itemizedItemsHeader;

  /// No description provided for @itemizedAddItem.
  ///
  /// In en, this message translates to:
  /// **'+ Add item'**
  String get itemizedAddItem;

  /// No description provided for @itemizedRemoveItem.
  ///
  /// In en, this message translates to:
  /// **'Remove item'**
  String get itemizedRemoveItem;

  /// No description provided for @itemizedItemLabelHint.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get itemizedItemLabelHint;

  /// No description provided for @itemizedWhoHadThis.
  ///
  /// In en, this message translates to:
  /// **'Who had this?'**
  String get itemizedWhoHadThis;

  /// No description provided for @itemizedEveryone.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get itemizedEveryone;

  /// No description provided for @itemizedEachOwes.
  ///
  /// In en, this message translates to:
  /// **'Each person owes'**
  String get itemizedEachOwes;

  /// No description provided for @itemizedItemsMatchTotal.
  ///
  /// In en, this message translates to:
  /// **'Items match total'**
  String get itemizedItemsMatchTotal;

  /// Itemized split: how far the line items are from the bill total (shown until they reconcile). {amount} is a formatted currency string, e.g. 'OMR 0.400'.
  ///
  /// In en, this message translates to:
  /// **'{amount} left'**
  String itemizedAmountLeft(Object amount);

  /// Itemized split: caption under a line item assigned to a single person. {name} is the assignee's display name.
  ///
  /// In en, this message translates to:
  /// **'for {name}'**
  String itemizedForName(Object name);

  /// Itemized split: subtitle on the How card showing the line-item count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String itemizedNItems(int count);

  /// No description provided for @itemizedNeedsSomeone.
  ///
  /// In en, this message translates to:
  /// **'Assign someone'**
  String get itemizedNeedsSomeone;

  /// No description provided for @adjustmentsHeader.
  ///
  /// In en, this message translates to:
  /// **'Adjustments'**
  String get adjustmentsHeader;

  /// No description provided for @adjustmentAddAction.
  ///
  /// In en, this message translates to:
  /// **'+ Add'**
  String get adjustmentAddAction;

  /// No description provided for @adjustmentRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove adjustment'**
  String get adjustmentRemove;

  /// No description provided for @adjustmentSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Add adjustment'**
  String get adjustmentSheetTitle;

  /// No description provided for @adjustmentTypeService.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get adjustmentTypeService;

  /// No description provided for @adjustmentTypeTax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get adjustmentTypeTax;

  /// No description provided for @adjustmentTypeTip.
  ///
  /// In en, this message translates to:
  /// **'Tip'**
  String get adjustmentTypeTip;

  /// No description provided for @adjustmentTypeDiscount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get adjustmentTypeDiscount;

  /// No description provided for @adjustmentAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get adjustmentAmountLabel;

  /// No description provided for @adjustmentSpreadHeader.
  ///
  /// In en, this message translates to:
  /// **'How to spread it'**
  String get adjustmentSpreadHeader;

  /// No description provided for @adjustmentAllocEqual.
  ///
  /// In en, this message translates to:
  /// **'Split equally'**
  String get adjustmentAllocEqual;

  /// No description provided for @adjustmentAllocProportional.
  ///
  /// In en, this message translates to:
  /// **'By item share'**
  String get adjustmentAllocProportional;

  /// No description provided for @adjustmentDiscountNote.
  ///
  /// In en, this message translates to:
  /// **'A discount is shared in proportion to what each person owes.'**
  String get adjustmentDiscountNote;

  /// No description provided for @adjustmentDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get adjustmentDone;

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

  /// No description provided for @settleUpIncompleteBalanceWarning.
  ///
  /// In en, this message translates to:
  /// **'This balance may be incomplete — some event data couldn\'t be loaded.'**
  String get settleUpIncompleteBalanceWarning;

  /// No description provided for @settleUpAmountGreaterThanZero.
  ///
  /// In en, this message translates to:
  /// **'Amount must be greater than zero'**
  String get settleUpAmountGreaterThanZero;

  /// No description provided for @settleUpEnterValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid amount'**
  String get settleUpEnterValidAmount;

  /// No description provided for @settleUpAmountExceedsOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Amount cannot exceed the outstanding balance of {amount}'**
  String settleUpAmountExceedsOutstanding(Object amount);

  /// No description provided for @settleUpBalanceChangedReviewAgain.
  ///
  /// In en, this message translates to:
  /// **'Balance changed while you were recording — it\'s now {amount}. Review and try again.'**
  String settleUpBalanceChangedReviewAgain(Object amount);

  /// No description provided for @settleUpRecorded.
  ///
  /// In en, this message translates to:
  /// **'Settlement recorded.'**
  String get settleUpRecorded;

  /// No description provided for @settleUpRecordedWillSync.
  ///
  /// In en, this message translates to:
  /// **'Settlement recorded — will sync when online.'**
  String get settleUpRecordedWillSync;

  /// No description provided for @settleUpRecordFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t record settlement. Check your connection and try again.'**
  String get settleUpRecordFailed;

  /// No description provided for @settleUpRecordFailedDenied.
  ///
  /// In en, this message translates to:
  /// **'This settlement wasn\'t allowed. Please check the details and try again.'**
  String get settleUpRecordFailedDenied;

  /// No description provided for @settleUpRecordFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t record settlement. Please try again.'**
  String get settleUpRecordFailedGeneric;

  /// Tooltip/label for the affordance that corrects a recorded settlement by recording an offsetting reverse payment (#283).
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get settleUpCorrect;

  /// Title of the confirmation dialog for correcting a recorded settlement (#283).
  ///
  /// In en, this message translates to:
  /// **'Correct this payment?'**
  String get settleUpCorrectTitle;

  /// Body of the settlement-correction confirm dialog (#283). Describes the offsetting reverse payment (the recipient pays the payer back) and that the original is preserved (append-only). Amount is pre-formatted code-first.
  ///
  /// In en, this message translates to:
  /// **'This records a reversing payment of {amount} from {recipient} back to {payer}. The original payment stays in your history.'**
  String settleUpCorrectBody(Object amount, Object recipient, Object payer);

  /// Confirm button on the settlement-correction dialog (#283).
  ///
  /// In en, this message translates to:
  /// **'Record correction'**
  String get settleUpCorrectConfirm;

  /// Note stored on the offsetting settlement created when a recorded payment is corrected (#283).
  ///
  /// In en, this message translates to:
  /// **'Correction of a recorded payment'**
  String get settleUpCorrectionNote;

  /// Short label shown above a reversing settlement row in Payment history so a correction reads as a correction, not a duplicate payment (#567).
  ///
  /// In en, this message translates to:
  /// **'Correction'**
  String get settleUpCorrectionTag;

  /// Title of the pre-settlement review sheet shown before event settle-up when review-worthy expenses exist (#204). Neutral, not accusatory.
  ///
  /// In en, this message translates to:
  /// **'Before you settle'**
  String get preSettleReviewTitle;

  /// Count summary line for exact-split expenses in the pre-settlement review sheet (#204).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 exact split} other{{count} exact splits}}'**
  String preSettleReviewExactCount(int count);

  /// Count summary line for custom-participant-split expenses in the pre-settlement review sheet (#204).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 custom participant split} other{{count} custom participant splits}}'**
  String preSettleReviewCustomCount(int count);

  /// Count summary line for personal-only expenses in the pre-settlement review sheet (#204).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 personal expense} other{{count} personal expenses}}'**
  String preSettleReviewPersonalCount(int count);

  /// Count summary line for unusually-large expenses in the pre-settlement review sheet (#204).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 large expense} other{{count} large expenses}}'**
  String preSettleReviewLargeCount(int count);

  /// Count summary line for expenses paid by a member who has since left the group in the pre-settlement review sheet (#204).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 paid by someone who left} other{{count} paid by people who left}}'**
  String preSettleReviewPayerLeftCount(int count);

  /// Per-item reason chip: the expense uses an exact split (#204).
  ///
  /// In en, this message translates to:
  /// **'Exact split'**
  String get preSettleReviewReasonExact;

  /// Per-item reason chip: the expense splits across a custom participant set (#204).
  ///
  /// In en, this message translates to:
  /// **'Custom participants'**
  String get preSettleReviewReasonCustom;

  /// Per-item reason chip: the expense is personal-only (#204).
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get preSettleReviewReasonPersonal;

  /// Per-item reason chip: the expense is unusually large for the event (#204).
  ///
  /// In en, this message translates to:
  /// **'Large amount'**
  String get preSettleReviewReasonLarge;

  /// Per-item reason chip: the expense was paid by a member who has since left the group (#204).
  ///
  /// In en, this message translates to:
  /// **'Payer left'**
  String get preSettleReviewReasonPayerLeft;

  /// Trailing line when more review-worthy expenses exist than the sheet lists (#204).
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String preSettleReviewMore(int count);

  /// Action that closes the sheet and opens the ledger to review expenses (#204).
  ///
  /// In en, this message translates to:
  /// **'Review expenses'**
  String get preSettleReviewReview;

  /// Action that dismisses the non-blocking pre-settlement review sheet and proceeds (#204).
  ///
  /// In en, this message translates to:
  /// **'Continue to settle'**
  String get preSettleReviewContinue;

  /// No description provided for @settleUpEveryoneEvenHeadline.
  ///
  /// In en, this message translates to:
  /// **'Everyone\'s even.'**
  String get settleUpEveryoneEvenHeadline;

  /// Forward-looking headline shown while transfers are still outstanding (not yet settled) — must not read as already-settled.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One transfer\nuntil everyone\'s even.} other{{count} transfers\nuntil everyone\'s even.}}'**
  String settleUpTransfersHeadline(int count);

  /// No description provided for @settleUpNoOptimizedPayments.
  ///
  /// In en, this message translates to:
  /// **'No optimized payments are needed across {subjectName}.'**
  String settleUpNoOptimizedPayments(Object subjectName);

  /// No description provided for @settleUpOptimizedPayments.
  ///
  /// In en, this message translates to:
  /// **'Optimized to reduce the number of payments across {subjectName}.'**
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

  /// Label on the #382 PR-5 stepped-settle card: records the user's debt with one counterparty across every currency bucket as a sequence of independent settlements. {name} is the counterparty's display name.
  ///
  /// In en, this message translates to:
  /// **'Settle all with {name}'**
  String settleUpSettleAllWith(Object name);

  /// Caption under the #382 PR-5 stepped-settle card showing how many separate per-currency payments the stepped walk will record.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 payment} other{{count} payments}}'**
  String settleUpSettleAllWithCount(int count);

  /// Overline on the record-payment sheet during a #382 PR-5 stepped multi-currency walk, e.g. '1 of 2'. {current} is the 1-based step number, {total} the bucket count.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String settleUpStepIndicator(int current, int total);

  /// Single summary snackbar after a #382 PR-5 stepped multi-currency walk records EVERY per-currency payment while online. {count} is the number of payments recorded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Recorded 1 payment.} other{Recorded {count} payments.}}'**
  String settleUpSteppedRecordedAll(int count);

  /// Single summary snackbar after a #382 PR-5 stepped walk records every per-currency payment while offline (queued for replay). {count} is the number of payments recorded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Recorded 1 payment — will sync when online.} other{Recorded {count} payments — will sync when online.}}'**
  String settleUpSteppedRecordedAllWillSync(int count);

  /// Single summary snackbar after a #382 PR-5 stepped walk stops early (cancelled or failed) having recorded only some of the per-currency payments. {recorded} is how many succeeded, {total} the planned count.
  ///
  /// In en, this message translates to:
  /// **'Recorded {recorded} of {total} payments.'**
  String settleUpSteppedRecordedPartial(int recorded, int total);

  /// Single summary snackbar after a #382 PR-5 stepped walk stops early having queued (offline) only some of the per-currency payments. {recorded} is how many were recorded, {total} the planned count.
  ///
  /// In en, this message translates to:
  /// **'Recorded {recorded} of {total} payments — will sync when online.'**
  String settleUpSteppedRecordedPartialWillSync(int recorded, int total);

  /// Title of the one-time settle-up explainer (#382 PR-5) shown when a group has balances in two or more currencies, explaining why currencies never net against each other.
  ///
  /// In en, this message translates to:
  /// **'Each currency settles separately'**
  String get currencyExplainerTitle;

  /// Body of the one-time settle-up currencies-don't-net explainer (#382 PR-5): Rihla does not invent exchange rates, currencies never net against each other, and users record one payment per currency.
  ///
  /// In en, this message translates to:
  /// **'We never invent exchange rates, so one currency can\'t cancel out another. You\'ll record one payment per currency.'**
  String get currencyExplainerBody;

  /// Dismiss button on the one-time settle-up currencies-don't-net explainer (#382 PR-5); tapping it hides the card for good.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get currencyExplainerGotIt;

  /// Persistent scope note (#717) on the event-scoped settle-up screen. Clarifies that recording a payment here only covers this one event's ledger, not the whole-group balance.
  ///
  /// In en, this message translates to:
  /// **'This settles balances for {eventName} only. Money owed across the rest of the group is settled from the group\'s Settle up.'**
  String settleScopeNoteEvent(String eventName);

  /// Persistent scope note (#717) on the group-scoped settle-up screen. Clarifies that this is the complete whole-group balance; since #752 a recorded payment decomposes into per-event settlement writes where it can attribute to a specific event, with any unattributable remainder tracked as a group-level settlement.
  ///
  /// In en, this message translates to:
  /// **'This is everyone\'s complete balance across the whole group. Recording a payment here spreads it over each event\'s ledger where it can — anything left over is tracked at group level.'**
  String get settleScopeNoteGroup;

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

  /// Affordance on a recorded-payment history tile (#359) that shares a plain-text receipt of the settlement via the iOS-safe shareText() helper.
  ///
  /// In en, this message translates to:
  /// **'Share receipt'**
  String get settleUpShareReceipt;

  /// #818 Wave 5.3: nav-only CTA on the standalone event settle-up screen, below payment history, that pushes the existing event recap route (Trip Receipt export lives there). Must never say 'receipt' — #359 collision with the per-payment share-receipt affordance above.
  ///
  /// In en, this message translates to:
  /// **'View recap & export'**
  String get settleUpViewRecapCta;

  /// First line of the shareable settlement receipt (#359): who paid whom, how much. The amount is pre-formatted code-first (e.g. 'OMR 5.000').
  ///
  /// In en, this message translates to:
  /// **'{payerName} paid {recipientName} {amount}'**
  String settleUpReceiptLine(
    Object payerName,
    Object recipientName,
    Object amount,
  );

  /// Second line of the shareable settlement receipt (#359): the date and the group/event name.
  ///
  /// In en, this message translates to:
  /// **'{date} · {subjectName}'**
  String settleUpReceiptContext(Object date, Object subjectName);

  /// Trailing line of the shareable settlement receipt (#359). Reinforces that Rihla records the payment but does not move money (#351).
  ///
  /// In en, this message translates to:
  /// **'— recorded in Rihla'**
  String get settleUpReceiptFooter;

  /// Share-sheet subject line for the settlement receipt (#359), used where the platform surfaces a subject (e.g. email).
  ///
  /// In en, this message translates to:
  /// **'Settlement receipt'**
  String get settleUpReceiptShareSubject;

  /// No description provided for @settleUpMarkThisPaidTitle.
  ///
  /// In en, this message translates to:
  /// **'Mark this paid?'**
  String get settleUpMarkThisPaidTitle;

  /// No description provided for @settleUpMarkThisReceivedTitle.
  ///
  /// In en, this message translates to:
  /// **'Mark this received?'**
  String get settleUpMarkThisReceivedTitle;

  /// Record-payment sheet title for the third-party variant (#595): the current user is neither the payer nor the recipient — they're recording a payment between two other people on the group's behalf.
  ///
  /// In en, this message translates to:
  /// **'Record this payment?'**
  String get settleUpRecordThisTitle;

  /// No description provided for @settleUpMarkThisPaidBody.
  ///
  /// In en, this message translates to:
  /// **'We\'ll close out the balance between {fromName} and {toName}.'**
  String settleUpMarkThisPaidBody(Object fromName, Object toName);

  /// Record-payment sheet title when the edited amount is below the full outstanding balance — a partial payment (#587). Perspective-neutral; the banner carries who-paid-whom.
  ///
  /// In en, this message translates to:
  /// **'Record a partial payment?'**
  String get settleUpRecordPartialTitle;

  /// Record-payment sheet body shown on a partial payment (edited < outstanding) (#587). Symmetric naming so it never debtor-frames the creditor's view.
  ///
  /// In en, this message translates to:
  /// **'This is a partial payment — the balance between {fromName} and {toName} stays open.'**
  String settleUpRecordPartialBody(Object fromName, Object toName);

  /// Live hint under the amount on a partial payment: what remains outstanding (outstanding − edited) after this settlement is recorded (#587).
  ///
  /// In en, this message translates to:
  /// **'{fromName} will still owe {toName} {amount} after this.'**
  String settleUpRemainingAfter(Object fromName, Object toName, Object amount);

  /// Title of the post-record nudge sheet (#367). Fires after a debtor records a settlement they made, offering to notify the creditor via WhatsApp. Past tense — the payment is already recorded.
  ///
  /// In en, this message translates to:
  /// **'Paid — let {name} know?'**
  String settleNotifySheetTitle(Object name);

  /// Sub-line under the #367 nudge title. Neutral wording; informing is optional and never a payment step.
  ///
  /// In en, this message translates to:
  /// **'Recorded — send a quick heads-up?'**
  String get settleNotifySheetBody;

  /// Uppercase label above the WhatsApp message preview on the #367 nudge sheet.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get settleNotifyMessageLabel;

  /// Caption explaining the numberless #367 handoff — Rihla stores no phone numbers; the user picks the recipient in WhatsApp.
  ///
  /// In en, this message translates to:
  /// **'You choose who to send it to in WhatsApp.'**
  String get settleNotifyPickChat;

  /// Dismiss button on the #367 nudge sheet — declines to notify; the settlement is already recorded.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get settleNotifyNotNow;

  /// Confirm button on the #367 nudge sheet — opens WhatsApp prefilled with the message.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get settleNotifyWhatsApp;

  /// Prefilled WhatsApp message for an EVENT-level settle (#367). Past tense. {amount} carries the live/edited amount, per-currency formatted and kept LTR-Latin in Arabic. Scope names the event AND its group to disambiguate same-named events across two shared groups.
  ///
  /// In en, this message translates to:
  /// **'Hey {recipientName}, I\'ve sent you {amount} for {eventName} in {groupName}.'**
  String settleNotifyMessageEvent(
    Object recipientName,
    Object amount,
    Object eventName,
    Object groupName,
  );

  /// Prefilled WhatsApp message for a GROUP-level settle (#367). Spans events, so it names only the group — never a single event. {amount} kept LTR-Latin in Arabic.
  ///
  /// In en, this message translates to:
  /// **'Hey {recipientName}, I\'ve sent you {amount} for {groupName}.'**
  String settleNotifyMessageGroup(
    Object recipientName,
    Object amount,
    Object groupName,
  );

  /// No description provided for @settleUpNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Add a note (optional)'**
  String get settleUpNoteHint;

  /// Heads-up on the record-payment sheet. Recording a settlement is unilateral and immediate — there is no confirmation step and no `confirmed` field — so the copy must not promise a notification or two-party confirmation (#281).
  ///
  /// In en, this message translates to:
  /// **'This records your payment to {name} immediately.'**
  String settleUpRecordsImmediately(Object name);

  /// Creditor variant of settleUpRecordsImmediately (#282): the current user is recording a payment they RECEIVED, so {name} is the payer (debtor). Same immediacy caveat as the debtor copy (#281).
  ///
  /// In en, this message translates to:
  /// **'This records {name}\'s payment to you immediately.'**
  String settleUpRecordsReceivedImmediately(Object name);

  /// Third-party variant of settleUpRecordsImmediately (#595): the current user is neither party, so the banner names BOTH the payer ({fromName}) and recipient ({toName}) — never 'your'/'you'. Same immediacy caveat as the debtor copy (#281).
  ///
  /// In en, this message translates to:
  /// **'This records {fromName}\'s payment to {toName} immediately.'**
  String settleUpRecordsForOthersImmediately(Object fromName, Object toName);

  /// Microcopy on the Mark-Paid/Mark-Received sheet (#351). Rihla is a ledger, not a payment processor; this sets the expectation that recording a settlement does not transfer any funds.
  ///
  /// In en, this message translates to:
  /// **'Rihla records the payment — it doesn\'t move money.'**
  String get settleUpDoesntMoveMoney;

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

  /// No description provided for @settleUpMarkReceived.
  ///
  /// In en, this message translates to:
  /// **'Mark received'**
  String get settleUpMarkReceived;

  /// Record-payment button label for the third-party variant (#595): a member recording a payment between two other people. Neutral — neither 'Mark paid' nor 'Mark received'.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get settleUpRecordPayment;

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

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @nameValidationEmpty.
  ///
  /// In en, this message translates to:
  /// **'Name can\'t be empty.'**
  String get nameValidationEmpty;

  /// No description provided for @nameValidationTooLong.
  ///
  /// In en, this message translates to:
  /// **'Keep it to {maxLength} characters or fewer.'**
  String nameValidationTooLong(int maxLength);

  /// No description provided for @nameValidationControlChars.
  ///
  /// In en, this message translates to:
  /// **'Remove line breaks or special characters.'**
  String get nameValidationControlChars;

  /// No description provided for @nameValidationReserved.
  ///
  /// In en, this message translates to:
  /// **'That name uses reserved wording.'**
  String get nameValidationReserved;

  /// No description provided for @homeActiveJourneys.
  ///
  /// In en, this message translates to:
  /// **'Active journeys'**
  String get homeActiveJourneys;

  /// No description provided for @homeSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get homeSeeAll;

  /// #807 — action beside the Active journeys header; it routes to the cross-group Activity log, so the label names the real destination (was the lying "See all").
  ///
  /// In en, this message translates to:
  /// **'View activity'**
  String get homeSeeActivity;

  /// No description provided for @homeGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get homeGroups;

  /// No description provided for @homeNewGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get homeNewGroup;

  /// No description provided for @homeRecently.
  ///
  /// In en, this message translates to:
  /// **'Recently'**
  String get homeRecently;

  /// No description provided for @homeNoActivityYet.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get homeNoActivityYet;

  /// No description provided for @homeTravellerFallback.
  ///
  /// In en, this message translates to:
  /// **'traveller'**
  String get homeTravellerFallback;

  /// No description provided for @homeStartFirstGroup.
  ///
  /// In en, this message translates to:
  /// **'Start your first group'**
  String get homeStartFirstGroup;

  /// No description provided for @homeStartFirstGroupBody.
  ///
  /// In en, this message translates to:
  /// **'Plan trips, track expenses, and settle up with friends.'**
  String get homeStartFirstGroupBody;

  /// No description provided for @homeCreateGroup.
  ///
  /// In en, this message translates to:
  /// **'Create Group'**
  String get homeCreateGroup;

  /// No description provided for @homeJoinGroup.
  ///
  /// In en, this message translates to:
  /// **'Join Group'**
  String get homeJoinGroup;

  /// No description provided for @homeRestoreWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google to restore'**
  String get homeRestoreWithGoogle;

  /// No description provided for @homeRestoreWithEmail.
  ///
  /// In en, this message translates to:
  /// **'Restore with email instead'**
  String get homeRestoreWithEmail;

  /// No description provided for @homeRestoreSectionCaption.
  ///
  /// In en, this message translates to:
  /// **'Been here before?'**
  String get homeRestoreSectionCaption;

  /// No description provided for @homeSetNameChip.
  ///
  /// In en, this message translates to:
  /// **'Set your name'**
  String get homeSetNameChip;

  /// No description provided for @homeGuestCaption.
  ///
  /// In en, this message translates to:
  /// **'Guest account — lives on this phone until you back it up in Profile.'**
  String get homeGuestCaption;

  /// No description provided for @restoreGoogleFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sign in with Google. Please try again.'**
  String get restoreGoogleFailed;

  /// No description provided for @restoreBlockedHasData.
  ///
  /// In en, this message translates to:
  /// **'Restoring switches to your saved account and leaves this phone\'s current groups behind — they\'re tied to a temporary identity that can\'t be moved. Resolve them first.'**
  String get restoreBlockedHasData;

  /// No description provided for @homeBackupNudgeTitle.
  ///
  /// In en, this message translates to:
  /// **'Back up your account'**
  String get homeBackupNudgeTitle;

  /// No description provided for @homeBackupNudgeBody.
  ///
  /// In en, this message translates to:
  /// **'Your groups and expenses live only on this phone. Link Google so a new phone, reinstall, or lost device can\'t erase them.'**
  String get homeBackupNudgeBody;

  /// No description provided for @homeBackupNudgeCta.
  ///
  /// In en, this message translates to:
  /// **'Link Google account'**
  String get homeBackupNudgeCta;

  /// No description provided for @homeBackupNudgeDismiss.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get homeBackupNudgeDismiss;

  /// No description provided for @homeErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get homeErrorTitle;

  /// No description provided for @homeErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again. Your groups are safely synced — we just need internet to fetch the latest.'**
  String get homeErrorMessage;

  /// No description provided for @homeCreateAGroup.
  ///
  /// In en, this message translates to:
  /// **'Create a Group'**
  String get homeCreateAGroup;

  /// No description provided for @homeJoinAGroup.
  ///
  /// In en, this message translates to:
  /// **'Join a Group'**
  String get homeJoinAGroup;

  /// No description provided for @homeGoodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get homeGoodMorning;

  /// No description provided for @homeGoodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get homeGoodAfternoon;

  /// No description provided for @homeGoodEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get homeGoodEvening;

  /// No description provided for @homeGreeting.
  ///
  /// In en, this message translates to:
  /// **'{greeting}, {name}'**
  String homeGreeting(Object greeting, Object name);

  /// No description provided for @homeNoUpcomingJourneys.
  ///
  /// In en, this message translates to:
  /// **'No upcoming or active journeys'**
  String get homeNoUpcomingJourneys;

  /// No description provided for @homeGroupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{memberCount, plural, =1{1 member} other{{memberCount} members}} · {eventCount, plural, =1{1 event} other{{eventCount} events}}'**
  String homeGroupSubtitle(int memberCount, int eventCount);

  /// No description provided for @homeTheyOweYou.
  ///
  /// In en, this message translates to:
  /// **'they owe you'**
  String get homeTheyOweYou;

  /// No description provided for @homeYouOwe.
  ///
  /// In en, this message translates to:
  /// **'you owe'**
  String get homeYouOwe;

  /// No description provided for @homeSettled.
  ///
  /// In en, this message translates to:
  /// **'settled'**
  String get homeSettled;

  /// No description provided for @homeAcrossAllJourneys.
  ///
  /// In en, this message translates to:
  /// **'Across all journeys'**
  String get homeAcrossAllJourneys;

  /// #807/#916 — visible cue on the tappable balance hero (its action is opening the per-group balance breakdown sheet, PR-5 §3); shown only when the card is tappable. Mirrors heroBreakdownTitle wording.
  ///
  /// In en, this message translates to:
  /// **'See balance by group'**
  String get homeBalanceHeroHint;

  /// PR-5 §3 — title of the sheet opened by tapping the balance hero; lists each group's non-zero net, per currency.
  ///
  /// In en, this message translates to:
  /// **'Balance by group'**
  String get heroBreakdownTitle;

  /// PR-5 §3 — empty state in the hero breakdown sheet when the user has zero net across every group.
  ///
  /// In en, this message translates to:
  /// **'You\'re all settled up'**
  String get heroBreakdownEmpty;

  /// No description provided for @homeNetYoureOwed.
  ///
  /// In en, this message translates to:
  /// **'Net — you\'re owed'**
  String get homeNetYoureOwed;

  /// No description provided for @homeNetYouOwe.
  ///
  /// In en, this message translates to:
  /// **'Net — you owe'**
  String get homeNetYouOwe;

  /// No description provided for @homeAllSettledAcrossJourneys.
  ///
  /// In en, this message translates to:
  /// **'All settled across journeys'**
  String get homeAllSettledAcrossJourneys;

  /// No description provided for @homeOwed.
  ///
  /// In en, this message translates to:
  /// **'owed'**
  String get homeOwed;

  /// No description provided for @homeOwe.
  ///
  /// In en, this message translates to:
  /// **'owe'**
  String get homeOwe;

  /// No description provided for @homeOwedToYou.
  ///
  /// In en, this message translates to:
  /// **'owed to you'**
  String get homeOwedToYou;

  /// No description provided for @homeBalanceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Balance unavailable'**
  String get homeBalanceUnavailable;

  /// Shown on the home balance hero when one or more events' money data failed to load, so the displayed cross-group balance is a partial sum (#244).
  ///
  /// In en, this message translates to:
  /// **'Some data couldn\'t load — balance may be incomplete'**
  String get homeBalanceIncompleteNotice;

  /// No description provided for @homeSpendingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Spending data unavailable'**
  String get homeSpendingUnavailable;

  /// No description provided for @homeWeeklySpending.
  ///
  /// In en, this message translates to:
  /// **'Weekly Spending ({currency})'**
  String homeWeeklySpending(Object currency);

  /// No description provided for @homeNoSpendingThisWeek.
  ///
  /// In en, this message translates to:
  /// **'No spending this week'**
  String get homeNoSpendingThisWeek;

  /// No description provided for @homeBottomNavGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get homeBottomNavGroups;

  /// No description provided for @homeBottomNavActivity.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get homeBottomNavActivity;

  /// No description provided for @homeBottomNavProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get homeBottomNavProfile;

  /// Header of the cross-group History tab screen
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTabTitle;

  /// No description provided for @homeQuickAddExpense.
  ///
  /// In en, this message translates to:
  /// **'Add Expense'**
  String get homeQuickAddExpense;

  /// No description provided for @homeQuickSettleUp.
  ///
  /// In en, this message translates to:
  /// **'Settle Up'**
  String get homeQuickSettleUp;

  /// No description provided for @homeQuickInviteFriend.
  ///
  /// In en, this message translates to:
  /// **'Invite Friend'**
  String get homeQuickInviteFriend;

  /// No description provided for @homeQuickActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get homeQuickActivity;

  /// No description provided for @addExpenseSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Add expense to…'**
  String get addExpenseSheetTitle;

  /// No description provided for @addExpenseSheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your open events, the one you\'re on first.'**
  String get addExpenseSheetSubtitle;

  /// No description provided for @addExpenseSheetSubtitleOngoing.
  ///
  /// In en, this message translates to:
  /// **'{groupName} · ongoing'**
  String addExpenseSheetSubtitleOngoing(Object groupName);

  /// No description provided for @addExpenseSheetSubtitleUpcoming.
  ///
  /// In en, this message translates to:
  /// **'{groupName} · in {days}d'**
  String addExpenseSheetSubtitleUpcoming(Object groupName, int days);

  /// No description provided for @addExpenseSheetBrowseAll.
  ///
  /// In en, this message translates to:
  /// **'Browse all groups'**
  String get addExpenseSheetBrowseAll;

  /// No description provided for @addExpenseSheetAllGroupsTitle.
  ///
  /// In en, this message translates to:
  /// **'All groups'**
  String get addExpenseSheetAllGroupsTitle;

  /// No description provided for @addExpenseSheetAllGroupsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a group, then one of its open events.'**
  String get addExpenseSheetAllGroupsSubtitle;

  /// No description provided for @addExpenseSheetOpenEventCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No open events} =1{1 open event} other{{count} open events}}'**
  String addExpenseSheetOpenEventCount(int count);

  /// #807 — fix-path caption on a disabled group tile in the quick-add picker (replaces the bare =0 count so the dead end explains itself).
  ///
  /// In en, this message translates to:
  /// **'No open events — open one in this group first'**
  String get addExpenseSheetNoOpenEventsHint;

  /// No description provided for @addExpenseSheetPickEventSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick an open event.'**
  String get addExpenseSheetPickEventSubtitle;

  /// No description provided for @addExpenseSheetEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing to add to yet'**
  String get addExpenseSheetEmptyTitle;

  /// No description provided for @addExpenseSheetEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Expenses live inside a group\'s events. Start a group — it comes with a ready ledger event.'**
  String get addExpenseSheetEmptyBody;

  /// No description provided for @addExpenseSheetLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your events. Try again.'**
  String get addExpenseSheetLoadFailed;

  /// No description provided for @activityTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activityTitle;

  /// No description provided for @activityCaption.
  ///
  /// In en, this message translates to:
  /// **'ACTIVITY'**
  String get activityCaption;

  /// No description provided for @activitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Across every journey, every group'**
  String get activitySubtitle;

  /// No description provided for @activityLoadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load activity'**
  String get activityLoadFailedTitle;

  /// No description provided for @activityLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get activityLoadFailedMessage;

  /// No description provided for @activityReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get activityReload;

  /// No description provided for @activityPartialFailure.
  ///
  /// In en, this message translates to:
  /// **'Some activity couldn\'t load'**
  String get activityPartialFailure;

  /// No description provided for @activityNoActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get activityNoActivityTitle;

  /// No description provided for @activityCrossGroupEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Activity from all your groups will appear here.'**
  String get activityCrossGroupEmptyMessage;

  /// No description provided for @activityEventEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Actions by you and your group members will appear here.'**
  String get activityEventEmptyMessage;

  /// No description provided for @activityGroupEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Group events, payments, and member changes will appear here.'**
  String get activityGroupEmptyMessage;

  /// No description provided for @activityNoFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches this filter'**
  String get activityNoFilterTitle;

  /// No description provided for @activityNoFilterMessage.
  ///
  /// In en, this message translates to:
  /// **'Try a different filter, or switch back to All.'**
  String get activityNoFilterMessage;

  /// No description provided for @activityFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get activityFilterAll;

  /// No description provided for @activityFilterSettlements.
  ///
  /// In en, this message translates to:
  /// **'Settlements'**
  String get activityFilterSettlements;

  /// No description provided for @activityFilterEvents.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get activityFilterEvents;

  /// No description provided for @activityFilterMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get activityFilterMembers;

  /// No description provided for @activityFilterExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get activityFilterExpenses;

  /// No description provided for @activitySearchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get activitySearchTooltip;

  /// No description provided for @activitySearchClose.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get activitySearchClose;

  /// No description provided for @activitySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search activity'**
  String get activitySearchHint;

  /// No description provided for @activitySearchNoMatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get activitySearchNoMatchesTitle;

  /// No description provided for @activitySearchNoMatchesMessage.
  ///
  /// In en, this message translates to:
  /// **'Nothing in your loaded activity matches \"{query}\".'**
  String activitySearchNoMatchesMessage(Object query);

  /// No description provided for @activitySearchOlder.
  ///
  /// In en, this message translates to:
  /// **'Search older activity'**
  String get activitySearchOlder;

  /// No description provided for @activitySearchLoadedCount.
  ///
  /// In en, this message translates to:
  /// **'Searching {count} loaded entries'**
  String activitySearchLoadedCount(int count);

  /// No description provided for @activityEventMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'This event no longer exists'**
  String get activityEventMissingTitle;

  /// No description provided for @activityEventMissingMessage.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted.'**
  String get activityEventMissingMessage;

  /// No description provided for @activityRelativeJustNow.
  ///
  /// In en, this message translates to:
  /// **'JUST NOW'**
  String get activityRelativeJustNow;

  /// No description provided for @activityRelativeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count}M'**
  String activityRelativeMinutes(int count);

  /// No description provided for @activityRelativeHours.
  ///
  /// In en, this message translates to:
  /// **'{count}H'**
  String activityRelativeHours(int count);

  /// No description provided for @activityRelativeDays.
  ///
  /// In en, this message translates to:
  /// **'{count}D'**
  String activityRelativeDays(int count);

  /// No description provided for @activitySomeone.
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get activitySomeone;

  /// No description provided for @activityAuditPayerLabel.
  ///
  /// In en, this message translates to:
  /// **'Payer'**
  String get activityAuditPayerLabel;

  /// No description provided for @activityEventMoneyCreated.
  ///
  /// In en, this message translates to:
  /// **'added an expense'**
  String get activityEventMoneyCreated;

  /// No description provided for @activityEventMoneyUpdated.
  ///
  /// In en, this message translates to:
  /// **'updated an expense'**
  String get activityEventMoneyUpdated;

  /// No description provided for @activityEventMoneyDeleted.
  ///
  /// In en, this message translates to:
  /// **'deleted an expense'**
  String get activityEventMoneyDeleted;

  /// No description provided for @activityEventGearCreated.
  ///
  /// In en, this message translates to:
  /// **'added a gear entry'**
  String get activityEventGearCreated;

  /// No description provided for @activityEventGearUpdated.
  ///
  /// In en, this message translates to:
  /// **'updated a gear entry'**
  String get activityEventGearUpdated;

  /// No description provided for @activityEventGearDeleted.
  ///
  /// In en, this message translates to:
  /// **'deleted a gear entry'**
  String get activityEventGearDeleted;

  /// No description provided for @activityEventDocsCreated.
  ///
  /// In en, this message translates to:
  /// **'added a document'**
  String get activityEventDocsCreated;

  /// No description provided for @activityEventDocsUpdated.
  ///
  /// In en, this message translates to:
  /// **'updated a document'**
  String get activityEventDocsUpdated;

  /// No description provided for @activityEventDocsDeleted.
  ///
  /// In en, this message translates to:
  /// **'deleted a document'**
  String get activityEventDocsDeleted;

  /// No description provided for @activityGroupSettlementDescription.
  ///
  /// In en, this message translates to:
  /// **'recorded a settlement'**
  String get activityGroupSettlementDescription;

  /// No description provided for @activitySettlementPaid.
  ///
  /// In en, this message translates to:
  /// **'paid {toName}'**
  String activitySettlementPaid(Object toName);

  /// No description provided for @activitySettlementReceived.
  ///
  /// In en, this message translates to:
  /// **'received a payment from {fromName}'**
  String activitySettlementReceived(Object fromName);

  /// No description provided for @activitySettlementBetween.
  ///
  /// In en, this message translates to:
  /// **'recorded a settlement from {fromName} to {toName}'**
  String activitySettlementBetween(Object fromName, Object toName);

  /// No description provided for @activityGroupEventCreatedGeneric.
  ///
  /// In en, this message translates to:
  /// **'created an event'**
  String get activityGroupEventCreatedGeneric;

  /// No description provided for @activityGroupEventCreated.
  ///
  /// In en, this message translates to:
  /// **'created {eventName}'**
  String activityGroupEventCreated(Object eventName);

  /// No description provided for @activityGroupEventDeletedGeneric.
  ///
  /// In en, this message translates to:
  /// **'deleted an event'**
  String get activityGroupEventDeletedGeneric;

  /// No description provided for @activityGroupEventDeleted.
  ///
  /// In en, this message translates to:
  /// **'deleted {eventName}'**
  String activityGroupEventDeleted(Object eventName);

  /// No description provided for @activityGroupMemberJoined.
  ///
  /// In en, this message translates to:
  /// **'joined the group'**
  String get activityGroupMemberJoined;

  /// No description provided for @activityGroupMemberLeft.
  ///
  /// In en, this message translates to:
  /// **'left the group'**
  String get activityGroupMemberLeft;

  /// No description provided for @activityGroupMemberRemoved.
  ///
  /// In en, this message translates to:
  /// **'removed {memberName} from the group'**
  String activityGroupMemberRemoved(Object memberName);

  /// No description provided for @activityGroupExpenseAdded.
  ///
  /// In en, this message translates to:
  /// **'added an expense in {eventName}'**
  String activityGroupExpenseAdded(Object eventName);

  /// No description provided for @activityGroupExpenseAddedGeneric.
  ///
  /// In en, this message translates to:
  /// **'added an expense'**
  String get activityGroupExpenseAddedGeneric;

  /// No description provided for @activityGroupExpenseEdited.
  ///
  /// In en, this message translates to:
  /// **'edited an expense in {eventName}'**
  String activityGroupExpenseEdited(Object eventName);

  /// No description provided for @activityGroupExpenseEditedGeneric.
  ///
  /// In en, this message translates to:
  /// **'edited an expense'**
  String get activityGroupExpenseEditedGeneric;

  /// No description provided for @activityGroupExpenseDeleted.
  ///
  /// In en, this message translates to:
  /// **'deleted an expense in {eventName}'**
  String activityGroupExpenseDeleted(Object eventName);

  /// No description provided for @activityGroupExpenseDeletedGeneric.
  ///
  /// In en, this message translates to:
  /// **'deleted an expense'**
  String get activityGroupExpenseDeletedGeneric;

  /// No description provided for @activityTitlePaymentRecorded.
  ///
  /// In en, this message translates to:
  /// **'Payment recorded'**
  String get activityTitlePaymentRecorded;

  /// No description provided for @activityTitleEventCreated.
  ///
  /// In en, this message translates to:
  /// **'Event created'**
  String get activityTitleEventCreated;

  /// No description provided for @activityTitleEventRemoved.
  ///
  /// In en, this message translates to:
  /// **'Event removed'**
  String get activityTitleEventRemoved;

  /// No description provided for @activityTitleMemberJoined.
  ///
  /// In en, this message translates to:
  /// **'Member joined'**
  String get activityTitleMemberJoined;

  /// No description provided for @activityTitleMemberLeft.
  ///
  /// In en, this message translates to:
  /// **'Member left'**
  String get activityTitleMemberLeft;

  /// No description provided for @activityTitleGeneric.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activityTitleGeneric;

  /// No description provided for @eventTypeTripLabel.
  ///
  /// In en, this message translates to:
  /// **'Trip'**
  String get eventTypeTripLabel;

  /// No description provided for @eventTypeTripShort.
  ///
  /// In en, this message translates to:
  /// **'TRIP'**
  String get eventTypeTripShort;

  /// No description provided for @eventTypeTripDescription.
  ///
  /// In en, this message translates to:
  /// **'Plan a shared trip with expenses and activity'**
  String get eventTypeTripDescription;

  /// No description provided for @eventTypeCampingLabel.
  ///
  /// In en, this message translates to:
  /// **'Camping'**
  String get eventTypeCampingLabel;

  /// No description provided for @eventTypeCampingShort.
  ///
  /// In en, this message translates to:
  /// **'CAMPING'**
  String get eventTypeCampingShort;

  /// No description provided for @eventTypeCampingDescription.
  ///
  /// In en, this message translates to:
  /// **'Outdoor trip with shared expense tracking'**
  String get eventTypeCampingDescription;

  /// No description provided for @eventTypeTravelLabel.
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get eventTypeTravelLabel;

  /// No description provided for @eventTypeTravelShort.
  ///
  /// In en, this message translates to:
  /// **'TRAVEL'**
  String get eventTypeTravelShort;

  /// No description provided for @eventTypeTravelDescription.
  ///
  /// In en, this message translates to:
  /// **'Journey with group expenses and activity'**
  String get eventTypeTravelDescription;

  /// No description provided for @eventTypeNightDayOutLabel.
  ///
  /// In en, this message translates to:
  /// **'Night/Day Out'**
  String get eventTypeNightDayOutLabel;

  /// No description provided for @eventTypeNightDayOutShort.
  ///
  /// In en, this message translates to:
  /// **'NIGHT/DAY OUT'**
  String get eventTypeNightDayOutShort;

  /// No description provided for @eventTypeNightDayOutDescription.
  ///
  /// In en, this message translates to:
  /// **'Quick outing with expense splitting'**
  String get eventTypeNightDayOutDescription;

  /// No description provided for @eventTypeCustomLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get eventTypeCustomLabel;

  /// No description provided for @eventTypeCustomShort.
  ///
  /// In en, this message translates to:
  /// **'EVENT'**
  String get eventTypeCustomShort;

  /// No description provided for @eventTypeCustomDescription.
  ///
  /// In en, this message translates to:
  /// **'Start from a flexible event setup'**
  String get eventTypeCustomDescription;

  /// No description provided for @eventNew.
  ///
  /// In en, this message translates to:
  /// **'New event'**
  String get eventNew;

  /// No description provided for @eventSecondEventHint.
  ///
  /// In en, this message translates to:
  /// **'Events split one group\'s spending into separate trips or outings — most groups only need one.'**
  String get eventSecondEventHint;

  /// No description provided for @eventNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Event Name'**
  String get eventNameLabel;

  /// No description provided for @eventNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Summer camping trip'**
  String get eventNameHint;

  /// No description provided for @eventDatesLabel.
  ///
  /// In en, this message translates to:
  /// **'Dates'**
  String get eventDatesLabel;

  /// No description provided for @eventOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'(optional)'**
  String get eventOptionalLabel;

  /// No description provided for @eventStartDate.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get eventStartDate;

  /// No description provided for @eventEndDate.
  ///
  /// In en, this message translates to:
  /// **'End date'**
  String get eventEndDate;

  /// No description provided for @eventCreate.
  ///
  /// In en, this message translates to:
  /// **'Create Event'**
  String get eventCreate;

  /// No description provided for @eventCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get eventCreating;

  /// No description provided for @eventSelectAtLeastOneParticipant.
  ///
  /// In en, this message translates to:
  /// **'Select at least one participant.'**
  String get eventSelectAtLeastOneParticipant;

  /// No description provided for @eventCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create event. Check your connection and try again.'**
  String get eventCreateFailed;

  /// No description provided for @eventCreatedWillSync.
  ///
  /// In en, this message translates to:
  /// **'Event saved — will sync when online.'**
  String get eventCreatedWillSync;

  /// No description provided for @eventParticipants.
  ///
  /// In en, this message translates to:
  /// **'Participants'**
  String get eventParticipants;

  /// No description provided for @eventSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get eventSelectAll;

  /// No description provided for @eventSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Event Settings'**
  String get eventSettingsTitle;

  /// No description provided for @eventSettingsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load settings'**
  String get eventSettingsLoadFailed;

  /// No description provided for @eventNotFound.
  ///
  /// In en, this message translates to:
  /// **'Event not found'**
  String get eventNotFound;

  /// No description provided for @eventDetailsSection.
  ///
  /// In en, this message translates to:
  /// **'EVENT DETAILS'**
  String get eventDetailsSection;

  /// No description provided for @eventNameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Event name can\'t be empty.'**
  String get eventNameEmpty;

  /// No description provided for @eventUpdated.
  ///
  /// In en, this message translates to:
  /// **'Event updated'**
  String get eventUpdated;

  /// No description provided for @eventUpdatedWillSync.
  ///
  /// In en, this message translates to:
  /// **'Event updated — will sync when online.'**
  String get eventUpdatedWillSync;

  /// No description provided for @eventSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save changes. Try again.'**
  String get eventSaveFailed;

  /// No description provided for @eventNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get eventNotSet;

  /// No description provided for @eventDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get eventDescriptionLabel;

  /// No description provided for @eventSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get eventSaveChanges;

  /// No description provided for @eventDangerZone.
  ///
  /// In en, this message translates to:
  /// **'DANGER ZONE'**
  String get eventDangerZone;

  /// No description provided for @eventUnsettledWarning.
  ///
  /// In en, this message translates to:
  /// **'This event has unsettled balances.'**
  String get eventUnsettledWarning;

  /// No description provided for @eventDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete event'**
  String get eventDelete;

  /// No description provided for @eventDeleteQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete this event?'**
  String get eventDeleteQuestion;

  /// No description provided for @eventDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete the event and all its expenses, settlements, and activity. This cannot be undone.'**
  String get eventDeleteBody;

  /// No description provided for @eventDeleteBodyWithUnsettled.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete the event and all its expenses, settlements, and activity. This cannot be undone.\n\nThis event has unsettled balances. Settle up before deleting, or proceed anyway.'**
  String get eventDeleteBodyWithUnsettled;

  /// No description provided for @eventKeepEvent.
  ///
  /// In en, this message translates to:
  /// **'Keep event'**
  String get eventKeepEvent;

  /// No description provided for @eventDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete event: {error}'**
  String eventDeleteFailed(Object error);

  /// No description provided for @eventClose.
  ///
  /// In en, this message translates to:
  /// **'Close event'**
  String get eventClose;

  /// No description provided for @eventReopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen event'**
  String get eventReopen;

  /// No description provided for @eventCloseQuestion.
  ///
  /// In en, this message translates to:
  /// **'Close this event?'**
  String get eventCloseQuestion;

  /// No description provided for @eventCloseBody.
  ///
  /// In en, this message translates to:
  /// **'Spending will be frozen — no new or edited expenses. You can still settle up, and you can reopen the event later.'**
  String get eventCloseBody;

  /// No description provided for @eventCloseConfirm.
  ///
  /// In en, this message translates to:
  /// **'Close event'**
  String get eventCloseConfirm;

  /// No description provided for @eventReopenQuestion.
  ///
  /// In en, this message translates to:
  /// **'Reopen this event?'**
  String get eventReopenQuestion;

  /// No description provided for @eventReopenBody.
  ///
  /// In en, this message translates to:
  /// **'Expenses can be added and edited again.'**
  String get eventReopenBody;

  /// No description provided for @eventReopenConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get eventReopenConfirm;

  /// No description provided for @eventCloseFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to close event: {error}'**
  String eventCloseFailed(Object error);

  /// No description provided for @eventReopenFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to reopen event: {error}'**
  String eventReopenFailed(Object error);

  /// No description provided for @eventClosedBannerBy.
  ///
  /// In en, this message translates to:
  /// **'Closed by {name} · spending frozen'**
  String eventClosedBannerBy(Object name);

  /// No description provided for @eventClosedBanner.
  ///
  /// In en, this message translates to:
  /// **'Closed · spending frozen'**
  String get eventClosedBanner;

  /// #708 — action on the closed-event banner that switches to the Recap tab. #807 unified the surface's name to "Recap"; "Trip Receipt" refers only to the CSV/PDF export (#704).
  ///
  /// In en, this message translates to:
  /// **'View recap'**
  String get eventViewReceipt;

  /// No description provided for @editorEventClosedTitle.
  ///
  /// In en, this message translates to:
  /// **'Event closed'**
  String get editorEventClosedTitle;

  /// No description provided for @editorEventClosedMessage.
  ///
  /// In en, this message translates to:
  /// **'This event is closed and its spending is frozen. Reopen it from Settings to add or edit expenses.'**
  String get editorEventClosedMessage;

  /// No description provided for @eventTabExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get eventTabExpenses;

  /// No description provided for @eventTabSettleUp.
  ///
  /// In en, this message translates to:
  /// **'Settle up'**
  String get eventTabSettleUp;

  /// No description provided for @eventTabActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get eventTabActivity;

  /// No description provided for @eventTabRecap.
  ///
  /// In en, this message translates to:
  /// **'Recap'**
  String get eventTabRecap;

  /// No description provided for @eventAddExpense.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get eventAddExpense;

  /// No description provided for @eventYourBalance.
  ///
  /// In en, this message translates to:
  /// **'Your balance'**
  String get eventYourBalance;

  /// No description provided for @eventYouAreOwed.
  ///
  /// In en, this message translates to:
  /// **'You are owed'**
  String get eventYouAreOwed;

  /// No description provided for @eventYouOwe.
  ///
  /// In en, this message translates to:
  /// **'You owe'**
  String get eventYouOwe;

  /// No description provided for @eventAllSettled.
  ///
  /// In en, this message translates to:
  /// **'All settled'**
  String get eventAllSettled;

  /// No description provided for @eventNothingToSettleYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing to settle yet'**
  String get eventNothingToSettleYet;

  /// No description provided for @eventEveryoneSquare.
  ///
  /// In en, this message translates to:
  /// **'Everyone is square on this trip.'**
  String get eventEveryoneSquare;

  /// No description provided for @eventAddFirstExpenseHint.
  ///
  /// In en, this message translates to:
  /// **'Add the first expense to start splitting.'**
  String get eventAddFirstExpenseHint;

  /// No description provided for @eventBreakdownOwesYou.
  ///
  /// In en, this message translates to:
  /// **'owes you'**
  String get eventBreakdownOwesYou;

  /// No description provided for @eventBreakdownYouOwe.
  ///
  /// In en, this message translates to:
  /// **'you owe'**
  String get eventBreakdownYouOwe;

  /// No description provided for @eventTripTotal.
  ///
  /// In en, this message translates to:
  /// **'Trip total'**
  String get eventTripTotal;

  /// No description provided for @eventTotalLabelCamping.
  ///
  /// In en, this message translates to:
  /// **'Camping total'**
  String get eventTotalLabelCamping;

  /// No description provided for @eventTotalLabelOuting.
  ///
  /// In en, this message translates to:
  /// **'Outing total'**
  String get eventTotalLabelOuting;

  /// No description provided for @eventTotalLabelEvent.
  ///
  /// In en, this message translates to:
  /// **'Event total'**
  String get eventTotalLabelEvent;

  /// No description provided for @eventExpenseCountInline.
  ///
  /// In en, this message translates to:
  /// **'· {count, plural, =1{1 expense} other{{count} expenses}}'**
  String eventExpenseCountInline(int count);

  /// No description provided for @eventLedgerLink.
  ///
  /// In en, this message translates to:
  /// **'Ledger →'**
  String get eventLedgerLink;

  /// No description provided for @eventRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get eventRecent;

  /// No description provided for @eventSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all →'**
  String get eventSeeAll;

  /// No description provided for @eventYouPaid.
  ///
  /// In en, this message translates to:
  /// **'You paid'**
  String get eventYouPaid;

  /// No description provided for @eventPaidByName.
  ///
  /// In en, this message translates to:
  /// **'{name} paid'**
  String eventPaidByName(Object name);

  /// No description provided for @eventAddFirstExpenseTitle.
  ///
  /// In en, this message translates to:
  /// **'Add the first expense'**
  String get eventAddFirstExpenseTitle;

  /// No description provided for @eventAddFirstExpenseBody.
  ///
  /// In en, this message translates to:
  /// **'Pick who paid, split it fairly.'**
  String get eventAddFirstExpenseBody;

  /// No description provided for @eventPeopleOverline.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 person} other{{count} people}}'**
  String eventPeopleOverline(int count);

  /// No description provided for @eventSplittingBetweenYouAndOthers.
  ///
  /// In en, this message translates to:
  /// **'{othersCount, plural, =1{Splitting between you and 1 other} other{Splitting between you and {othersCount} others}}'**
  String eventSplittingBetweenYouAndOthers(int othersCount);

  /// No description provided for @eventYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get eventYou;

  /// No description provided for @eventDayOf.
  ///
  /// In en, this message translates to:
  /// **'Day {currentDay} of {totalDays}'**
  String eventDayOf(int currentDay, int totalDays);

  /// No description provided for @eventLoadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load event'**
  String get eventLoadFailedTitle;

  /// No description provided for @eventMissingMessage.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted, or the link is incorrect.'**
  String get eventMissingMessage;

  /// No description provided for @eventSemanticCard.
  ///
  /// In en, this message translates to:
  /// **'{eventName}, {count, plural, =1{1 person} other{{count} people}}'**
  String eventSemanticCard(Object eventName, int count);

  /// No description provided for @eventYouOweAmount.
  ///
  /// In en, this message translates to:
  /// **'You owe {currency} {amount}'**
  String eventYouOweAmount(Object amount, Object currency);

  /// No description provided for @eventYouAreOwedAmount.
  ///
  /// In en, this message translates to:
  /// **'You are owed {currency} {amount}'**
  String eventYouAreOwedAmount(Object amount, Object currency);

  /// No description provided for @groupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Group Name'**
  String get groupNameLabel;

  /// No description provided for @groupNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Family trip'**
  String get groupNameHint;

  /// No description provided for @groupYourNameInGroupLabel.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get groupYourNameInGroupLabel;

  /// No description provided for @groupYourNameHint.
  ///
  /// In en, this message translates to:
  /// **'how friends will see you'**
  String get groupYourNameHint;

  /// No description provided for @groupDifferentNameHelper.
  ///
  /// In en, this message translates to:
  /// **'Shown in all your groups. Changing it anywhere updates it everywhere.'**
  String get groupDifferentNameHelper;

  /// No description provided for @groupCreateError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String groupCreateError(Object error);

  /// No description provided for @groupCreatedWillSync.
  ///
  /// In en, this message translates to:
  /// **'Group created — will sync when online.'**
  String get groupCreatedWillSync;

  /// No description provided for @groupNew.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get groupNew;

  /// No description provided for @groupEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit group'**
  String get groupEditTitle;

  /// No description provided for @groupCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get groupCreate;

  /// No description provided for @groupMoodTitle.
  ///
  /// In en, this message translates to:
  /// **'Who\'s coming along?'**
  String get groupMoodTitle;

  /// No description provided for @groupMoodBody.
  ///
  /// In en, this message translates to:
  /// **'A group is a circle of people you share expenses with — a household, a travel crew, a project team.'**
  String get groupMoodBody;

  /// #287 trip-stamps: section header above the group stamp picker on the Create-Group screen.
  ///
  /// In en, this message translates to:
  /// **'Stamp'**
  String get groupGlyph;

  /// #287 trip-stamps: label for the ink-colour swatch row in the group stamp picker.
  ///
  /// In en, this message translates to:
  /// **'Ink'**
  String get groupStampInk;

  /// #287 trip-stamps: label for the symbol grid in the group stamp picker.
  ///
  /// In en, this message translates to:
  /// **'Symbol'**
  String get groupStampSymbol;

  /// #287 trip-stamps: muted caption explaining that, with no symbol chosen, the group's first initial is used as the stamp.
  ///
  /// In en, this message translates to:
  /// **'Your initial is the default'**
  String get groupStampMonogramHint;

  /// No description provided for @groupDefaultCurrency.
  ///
  /// In en, this message translates to:
  /// **'Default currency'**
  String get groupDefaultCurrency;

  /// No description provided for @groupCreatorTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re the creator.'**
  String get groupCreatorTitle;

  /// No description provided for @groupCreatorBody.
  ///
  /// In en, this message translates to:
  /// **'Once created, share an invite code to bring others in.'**
  String get groupCreatorBody;

  /// No description provided for @groupInviteCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Invite code copied'**
  String get groupInviteCodeCopied;

  /// No description provided for @groupShareMessage.
  ///
  /// In en, this message translates to:
  /// **'Join my group on Rihla! Use code {code} to join.'**
  String groupShareMessage(Object code);

  /// No description provided for @groupShareSubject.
  ///
  /// In en, this message translates to:
  /// **'Join {name}'**
  String groupShareSubject(Object name);

  /// No description provided for @groupShareCodeWithGroup.
  ///
  /// In en, this message translates to:
  /// **'Share this code with your group'**
  String get groupShareCodeWithGroup;

  /// No description provided for @groupCopyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy Code'**
  String get groupCopyCode;

  /// No description provided for @groupShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get groupShare;

  /// Label on the invite-sheet button that opens WhatsApp prefilled with the join link (#354). Falls back to the OS share sheet when WhatsApp isn't installed.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get groupShareViaWhatsApp;

  /// No description provided for @groupJoinTitle.
  ///
  /// In en, this message translates to:
  /// **'Join a Group'**
  String get groupJoinTitle;

  /// No description provided for @groupJoinCta.
  ///
  /// In en, this message translates to:
  /// **'Join Group'**
  String get groupJoinCta;

  /// No description provided for @groupJoining.
  ///
  /// In en, this message translates to:
  /// **'Joining…'**
  String get groupJoining;

  /// No description provided for @groupYourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get groupYourName;

  /// No description provided for @groupJoinNameHint.
  ///
  /// In en, this message translates to:
  /// **'how the group will see you'**
  String get groupJoinNameHint;

  /// No description provided for @groupInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get groupInviteCode;

  /// No description provided for @groupInviteCodeHelper.
  ///
  /// In en, this message translates to:
  /// **'Ask a group member for their 6-character code'**
  String get groupInviteCodeHelper;

  /// No description provided for @groupJoinHintTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ll see balances right away.'**
  String get groupJoinHintTitle;

  /// No description provided for @groupJoinHintBody.
  ///
  /// In en, this message translates to:
  /// **'Joining is instant — approval is only needed if you\'re claiming an existing member\'s spot.'**
  String get groupJoinHintBody;

  /// No description provided for @groupJoinMoodTitle.
  ///
  /// In en, this message translates to:
  /// **'Got an invite?'**
  String get groupJoinMoodTitle;

  /// No description provided for @groupJoinMoodBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-character code a friend gave you. We will drop you straight into the group.'**
  String get groupJoinMoodBody;

  /// No description provided for @groupJoinInvalidCode.
  ///
  /// In en, this message translates to:
  /// **'That code doesn\'t match any group. Check the code and try again.'**
  String get groupJoinInvalidCode;

  /// No description provided for @groupJoinAlreadyMember.
  ///
  /// In en, this message translates to:
  /// **'You\'re already in this group.'**
  String get groupJoinAlreadyMember;

  /// No description provided for @groupJoinNameTaken.
  ///
  /// In en, this message translates to:
  /// **'That name\'s already used in this group. Please pick a different name.'**
  String get groupJoinNameTaken;

  /// No description provided for @displayNameTakenInGroup.
  ///
  /// In en, this message translates to:
  /// **'That name\'s already used in {groupName}. Please pick a different name.'**
  String displayNameTakenInGroup(Object groupName);

  /// No description provided for @groupJoinTooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again later.'**
  String get groupJoinTooManyAttempts;

  /// No description provided for @groupJoinPleaseSignIn.
  ///
  /// In en, this message translates to:
  /// **'Please sign in and try again.'**
  String get groupJoinPleaseSignIn;

  /// No description provided for @groupJoinDeviceVerificationFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not verify this device. Try again, or update from the Play Store.'**
  String get groupJoinDeviceVerificationFailed;

  /// No description provided for @groupJoinFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t join the group. Check your connection and try again.'**
  String get groupJoinFailed;

  /// No description provided for @groupMemberJoinedDescription.
  ///
  /// In en, this message translates to:
  /// **'joined the group'**
  String get groupMemberJoinedDescription;

  /// No description provided for @groupMemberLeftDescription.
  ///
  /// In en, this message translates to:
  /// **'left the group'**
  String get groupMemberLeftDescription;

  /// No description provided for @groupEvents.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get groupEvents;

  /// No description provided for @groupMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get groupMembers;

  /// No description provided for @groupPeople.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get groupPeople;

  /// No description provided for @groupInsightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get groupInsightsTitle;

  /// No description provided for @insightsTotalSpent.
  ///
  /// In en, this message translates to:
  /// **'Total spent'**
  String get insightsTotalSpent;

  /// No description provided for @insightsTopEvent.
  ///
  /// In en, this message translates to:
  /// **'Biggest event'**
  String get insightsTopEvent;

  /// No description provided for @insightsTopPayer.
  ///
  /// In en, this message translates to:
  /// **'Fronted the most'**
  String get insightsTopPayer;

  /// No description provided for @insightsTopConsumer.
  ///
  /// In en, this message translates to:
  /// **'Biggest share'**
  String get insightsTopConsumer;

  /// No description provided for @groupNoEventsTitle.
  ///
  /// In en, this message translates to:
  /// **'No events yet'**
  String get groupNoEventsTitle;

  /// No description provided for @groupNoEventsMessage.
  ///
  /// In en, this message translates to:
  /// **'Create your first event to start planning together.'**
  String get groupNoEventsMessage;

  /// No description provided for @groupCreateEvent.
  ///
  /// In en, this message translates to:
  /// **'Create Event'**
  String get groupCreateEvent;

  /// No description provided for @groupInvitePeople.
  ///
  /// In en, this message translates to:
  /// **'Invite people'**
  String get groupInvitePeople;

  /// No description provided for @groupLoadEventsFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load events'**
  String get groupLoadEventsFailed;

  /// No description provided for @groupMemberCountCaps.
  ///
  /// In en, this message translates to:
  /// **'GROUP · {count, plural, =1{1 MEMBER} other{{count} MEMBERS}}'**
  String groupMemberCountCaps(int count);

  /// No description provided for @groupMoreTooltip.
  ///
  /// In en, this message translates to:
  /// **'Group options'**
  String get groupMoreTooltip;

  /// No description provided for @groupSettings.
  ///
  /// In en, this message translates to:
  /// **'Group settings'**
  String get groupSettings;

  /// No description provided for @groupActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get groupActivity;

  /// No description provided for @groupYourBalanceHere.
  ///
  /// In en, this message translates to:
  /// **'Your balance here'**
  String get groupYourBalanceHere;

  /// No description provided for @groupTheyOweYou.
  ///
  /// In en, this message translates to:
  /// **'they owe you'**
  String get groupTheyOweYou;

  /// No description provided for @groupYouOwe.
  ///
  /// In en, this message translates to:
  /// **'you owe'**
  String get groupYouOwe;

  /// No description provided for @groupAllSettled.
  ///
  /// In en, this message translates to:
  /// **'all settled'**
  String get groupAllSettled;

  /// No description provided for @groupSettleUp.
  ///
  /// In en, this message translates to:
  /// **'Settle up'**
  String get groupSettleUp;

  /// No description provided for @groupEventEnds.
  ///
  /// In en, this message translates to:
  /// **'ends {date}'**
  String groupEventEnds(Object date);

  /// No description provided for @groupYourShare.
  ///
  /// In en, this message translates to:
  /// **'your share'**
  String get groupYourShare;

  /// No description provided for @groupNoShare.
  ///
  /// In en, this message translates to:
  /// **'no share'**
  String get groupNoShare;

  /// No description provided for @groupMembersLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load members'**
  String get groupMembersLoadFailed;

  /// No description provided for @groupMembersLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading members…'**
  String get groupMembersLoading;

  /// No description provided for @groupFormerMember.
  ///
  /// In en, this message translates to:
  /// **'Former member'**
  String get groupFormerMember;

  /// No description provided for @groupRoleYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get groupRoleYou;

  /// No description provided for @groupRoleCreator.
  ///
  /// In en, this message translates to:
  /// **'Creator'**
  String get groupRoleCreator;

  /// No description provided for @groupBalanceShownAbove.
  ///
  /// In en, this message translates to:
  /// **'shown above'**
  String get groupBalanceShownAbove;

  /// No description provided for @groupLoadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load group'**
  String get groupLoadFailedTitle;

  /// No description provided for @groupNoAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'You no longer have access'**
  String get groupNoAccessTitle;

  /// No description provided for @groupNoAccessMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'re no longer a member of this group, or it\'s no longer shared with you.'**
  String get groupNoAccessMessage;

  /// No description provided for @groupNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Group not found'**
  String get groupNotFoundTitle;

  /// No description provided for @groupNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted, or the link is incorrect.'**
  String get groupNotFoundMessage;

  /// No description provided for @groupBackHome.
  ///
  /// In en, this message translates to:
  /// **'Back home'**
  String get groupBackHome;

  /// No description provided for @groupSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Group settings'**
  String get groupSettingsTitle;

  /// No description provided for @groupDefaults.
  ///
  /// In en, this message translates to:
  /// **'Defaults'**
  String get groupDefaults;

  /// No description provided for @groupCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get groupCurrency;

  /// No description provided for @groupCurrencyLockedNote.
  ///
  /// In en, this message translates to:
  /// **'Currency is set when the group is created and can\'t be changed.'**
  String get groupCurrencyLockedNote;

  /// #807 — caption under the members card for non-creators, explaining why the add/remove affordances are absent (mirrors the locked-currency-note pattern).
  ///
  /// In en, this message translates to:
  /// **'Only the group creator can add or remove members.'**
  String get groupMembersCreatorOnlyNote;

  /// No description provided for @groupSettingsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load settings'**
  String get groupSettingsLoadFailed;

  /// No description provided for @groupTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get groupTryAgain;

  /// No description provided for @groupInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get groupInvite;

  /// No description provided for @groupCreatedDateCurrency.
  ///
  /// In en, this message translates to:
  /// **'Created {date} · {currency}'**
  String groupCreatedDateCurrency(Object date, Object currency);

  /// No description provided for @groupAnyoneWithCodeCanJoin.
  ///
  /// In en, this message translates to:
  /// **'Anyone with the code can join'**
  String get groupAnyoneWithCodeCanJoin;

  /// No description provided for @groupEditNameSemantic.
  ///
  /// In en, this message translates to:
  /// **'Edit group name'**
  String get groupEditNameSemantic;

  /// No description provided for @groupCopyInviteCodeSemantic.
  ///
  /// In en, this message translates to:
  /// **'Copy invite code'**
  String get groupCopyInviteCodeSemantic;

  /// No description provided for @groupShowQrCodeSemantic.
  ///
  /// In en, this message translates to:
  /// **'Show QR code'**
  String get groupShowQrCodeSemantic;

  /// No description provided for @groupShowQrCode.
  ///
  /// In en, this message translates to:
  /// **'Show QR code'**
  String get groupShowQrCode;

  /// No description provided for @groupShareInviteSemantic.
  ///
  /// In en, this message translates to:
  /// **'Share invite'**
  String get groupShareInviteSemantic;

  /// No description provided for @groupUpdateNameFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update name: {error}'**
  String groupUpdateNameFailed(Object error);

  /// No description provided for @groupDangerZone.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get groupDangerZone;

  /// No description provided for @groupDangerZoneCreatorOnly.
  ///
  /// In en, this message translates to:
  /// **'Danger zone · Creator only'**
  String get groupDangerZoneCreatorOnly;

  /// No description provided for @groupLeaveThisGroup.
  ///
  /// In en, this message translates to:
  /// **'Leave this group'**
  String get groupLeaveThisGroup;

  /// No description provided for @groupLeaveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ll lose access to its events and expenses.'**
  String get groupLeaveSubtitle;

  /// No description provided for @groupLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get groupLeave;

  /// No description provided for @groupDeleteThisGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete this group'**
  String get groupDeleteThisGroup;

  /// No description provided for @groupDeleteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'All events and expenses will be lost.'**
  String get groupDeleteSubtitle;

  /// No description provided for @groupDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get groupDelete;

  /// No description provided for @groupLeaveQuestion.
  ///
  /// In en, this message translates to:
  /// **'Leave group?'**
  String get groupLeaveQuestion;

  /// No description provided for @groupLeaveBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll lose access to all events and data in this group.'**
  String get groupLeaveBody;

  /// No description provided for @groupStayInGroup.
  ///
  /// In en, this message translates to:
  /// **'Stay in group'**
  String get groupStayInGroup;

  /// No description provided for @groupLeaveGroup.
  ///
  /// In en, this message translates to:
  /// **'Leave group'**
  String get groupLeaveGroup;

  /// No description provided for @groupSettleBeforeLeaving.
  ///
  /// In en, this message translates to:
  /// **'Settle up before leaving the group.'**
  String get groupSettleBeforeLeaving;

  /// No description provided for @groupFailedLeave.
  ///
  /// In en, this message translates to:
  /// **'Failed to leave group: {error}'**
  String groupFailedLeave(Object error);

  /// No description provided for @groupSettleBeforeDeleting.
  ///
  /// In en, this message translates to:
  /// **'All members must settle up before deleting the group.'**
  String get groupSettleBeforeDeleting;

  /// No description provided for @groupFailedDelete.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete group: {error}'**
  String groupFailedDelete(Object error);

  /// No description provided for @groupDeleteSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this group?'**
  String get groupDeleteSheetTitle;

  /// No description provided for @groupDeleteSheetRemovesPrefix.
  ///
  /// In en, this message translates to:
  /// **'Removes '**
  String get groupDeleteSheetRemovesPrefix;

  /// No description provided for @groupDeleteSheetMembersBody.
  ///
  /// In en, this message translates to:
  /// **' for all {count} members. Events, expenses, and balances inside it are erased. '**
  String groupDeleteSheetMembersBody(int count);

  /// No description provided for @groupDeleteSheetEveryoneBody.
  ///
  /// In en, this message translates to:
  /// **' for everyone. Events, expenses, and balances inside it are erased. '**
  String get groupDeleteSheetEveryoneBody;

  /// No description provided for @groupDeleteSheetUndo.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be undone.'**
  String get groupDeleteSheetUndo;

  /// No description provided for @groupDeleteSheetTypePrefix.
  ///
  /// In en, this message translates to:
  /// **'TYPE '**
  String get groupDeleteSheetTypePrefix;

  /// No description provided for @groupDeleteSheetTypeSuffix.
  ///
  /// In en, this message translates to:
  /// **' TO CONFIRM'**
  String get groupDeleteSheetTypeSuffix;

  /// No description provided for @groupDeleteSheetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get groupDeleteSheetConfirm;

  /// No description provided for @groupScanToJoin.
  ///
  /// In en, this message translates to:
  /// **'Scan to join'**
  String get groupScanToJoin;

  /// No description provided for @groupInviteQrCode.
  ///
  /// In en, this message translates to:
  /// **'Invite QR code'**
  String get groupInviteQrCode;

  /// No description provided for @groupOrEnterCode.
  ///
  /// In en, this message translates to:
  /// **'OR ENTER CODE'**
  String get groupOrEnterCode;

  /// No description provided for @groupCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get groupCopyLink;

  /// No description provided for @groupLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get groupLinkCopied;

  /// No description provided for @groupShareInviteMessage.
  ///
  /// In en, this message translates to:
  /// **'Join \'{groupName}\' on Rihla: {uri} or use code {code}.'**
  String groupShareInviteMessage(Object groupName, Object uri, Object code);

  /// No description provided for @groupShareInviteSubject.
  ///
  /// In en, this message translates to:
  /// **'Join \'{groupName}\' on Rihla'**
  String groupShareInviteSubject(Object groupName);

  /// No description provided for @groupAddMemberAction.
  ///
  /// In en, this message translates to:
  /// **'Add member'**
  String get groupAddMemberAction;

  /// Pill on a member tile (#278) for a placeholder ('shadow') member added by name who hasn't joined via invite code yet.
  ///
  /// In en, this message translates to:
  /// **'Not joined yet'**
  String get groupShadowNotJoinedBadge;

  /// Title of the #278 in-group sheet where the creator adds a placeholder member by name.
  ///
  /// In en, this message translates to:
  /// **'Add a person'**
  String get groupAddPersonTitle;

  /// Subtitle under the #278 add-a-person sheet title explaining the placeholder is filled in when the real person joins.
  ///
  /// In en, this message translates to:
  /// **'Add someone by name now; they can join later with the invite code.'**
  String get groupAddPersonSubtitle;

  /// Submit button in the #278 add-a-person sheet.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get groupAddPersonAction;

  /// No description provided for @groupRemoveMemberTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from group'**
  String groupRemoveMemberTooltip(Object name);

  /// No description provided for @groupRoleMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get groupRoleMember;

  /// No description provided for @groupSettleWithBeforeRemoving.
  ///
  /// In en, this message translates to:
  /// **'Settle up with {name} before removing them.'**
  String groupSettleWithBeforeRemoving(Object name);

  /// No description provided for @groupFailedRemoveMember.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove {name}: {error}'**
  String groupFailedRemoveMember(Object name, Object error);

  /// No description provided for @onboardingBrandKicker.
  ///
  /// In en, this message translates to:
  /// **'RIHLA · ر.ح.ل.ة'**
  String get onboardingBrandKicker;

  /// No description provided for @onboardingBrandHeadlineLead.
  ///
  /// In en, this message translates to:
  /// **'Trips,\ntallied with\n'**
  String get onboardingBrandHeadlineLead;

  /// No description provided for @onboardingBrandHeadlineAccent.
  ///
  /// In en, this message translates to:
  /// **'care'**
  String get onboardingBrandHeadlineAccent;

  /// No description provided for @onboardingBrandHeadlineSuffix.
  ///
  /// In en, this message translates to:
  /// **'.'**
  String get onboardingBrandHeadlineSuffix;

  /// No description provided for @onboardingBrandBody.
  ///
  /// In en, this message translates to:
  /// **'A travel ledger for friends, families and crews who want the trip to be the memory — not the math.'**
  String get onboardingBrandBody;

  /// No description provided for @onboardingBegin.
  ///
  /// In en, this message translates to:
  /// **'Begin'**
  String get onboardingBegin;

  /// No description provided for @onboardingHowTitle.
  ///
  /// In en, this message translates to:
  /// **'Three ways\nit travels with you.'**
  String get onboardingHowTitle;

  /// No description provided for @onboardingHowGroupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Groups for the people you travel with'**
  String get onboardingHowGroupsTitle;

  /// No description provided for @onboardingHowGroupsBody.
  ///
  /// In en, this message translates to:
  /// **'A travel crew, a roommates group, a family. People stay; events come and go.'**
  String get onboardingHowGroupsBody;

  /// No description provided for @onboardingHowEventsTitle.
  ///
  /// In en, this message translates to:
  /// **'Events for the trips & nights out'**
  String get onboardingHowEventsTitle;

  /// No description provided for @onboardingHowEventsBody.
  ///
  /// In en, this message translates to:
  /// **'Trips, dinners, weekends. Each gets a cover, a dates window, and its own ledger.'**
  String get onboardingHowEventsBody;

  /// No description provided for @onboardingHowExpensesTitle.
  ///
  /// In en, this message translates to:
  /// **'Expenses split in three taps'**
  String get onboardingHowExpensesTitle;

  /// No description provided for @onboardingHowExpensesBody.
  ///
  /// In en, this message translates to:
  /// **'Equally, by share, or however. Math happens in the background — settle when you like.'**
  String get onboardingHowExpensesBody;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'A few things\nbefore we begin.'**
  String get onboardingSetupTitle;

  /// No description provided for @onboardingNameSection.
  ///
  /// In en, this message translates to:
  /// **'What should we call you?'**
  String get onboardingNameSection;

  /// No description provided for @onboardingCurrencySection.
  ///
  /// In en, this message translates to:
  /// **'Home currency'**
  String get onboardingCurrencySection;

  /// No description provided for @onboardingCurrencyHelper.
  ///
  /// In en, this message translates to:
  /// **'Each group can override this later.'**
  String get onboardingCurrencyHelper;

  /// No description provided for @onboardingNotificationsSection.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get onboardingNotificationsSection;

  /// No description provided for @onboardingOpenRihla.
  ///
  /// In en, this message translates to:
  /// **'Open Rihla'**
  String get onboardingOpenRihla;

  /// No description provided for @onboardingNameHint.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get onboardingNameHint;

  /// No description provided for @onboardingCurrencySemantics.
  ///
  /// In en, this message translates to:
  /// **'{currency} currency'**
  String onboardingCurrencySemantics(Object currency);

  /// No description provided for @onboardingActivitySettlesTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity & settles'**
  String get onboardingActivitySettlesTitle;

  /// No description provided for @onboardingActivitySettlesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When friends add or pay'**
  String get onboardingActivitySettlesSubtitle;

  /// No description provided for @onboardingWeeklyDigestTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly digest'**
  String get onboardingWeeklyDigestTitle;

  /// No description provided for @onboardingWeeklyDigestSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A Sunday summary'**
  String get onboardingWeeklyDigestSubtitle;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingStepSemantics.
  ///
  /// In en, this message translates to:
  /// **'Onboarding step {active} of {count}'**
  String onboardingStepSemantics(int active, int count);

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

  /// No description provided for @expenseSuccessWillSync.
  ///
  /// In en, this message translates to:
  /// **'SAVED — WILL SYNC'**
  String get expenseSuccessWillSync;

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

  /// Generic 'Not Found' label used in module headers and error states; pre-added for cross-feature reuse.
  ///
  /// In en, this message translates to:
  /// **'Not Found'**
  String get commonNotFound;

  /// Email field label reused across the auth recover/link flows.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get commonEmail;

  /// Placeholder example shown inside the Email text field across auth flows.
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get commonEmailHintExample;

  /// Friendly greeting shown both on the recover-from-email screen heading and the recovery-completion snackbar.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get authWelcomeBack;

  /// App bar title on the Recover-from-email screen (Home empty state → 'I had Rihla before — restore').
  ///
  /// In en, this message translates to:
  /// **'Restore from email'**
  String get authRecoverTitle;

  /// Body copy under the Welcome back heading on the recover-from-email screen.
  ///
  /// In en, this message translates to:
  /// **'Enter the email you linked on your old device. We\'ll send a one-tap sign-in link.'**
  String get authRecoverDescription;

  /// Primary CTA on the recover-from-email screen — sends the sign-in link.
  ///
  /// In en, this message translates to:
  /// **'Send recovery link'**
  String get authRecoverSubmit;

  /// Catch-all error shown when sending the recovery/link email fails for an unknown reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the link. Check your connection and try again.'**
  String get authErrorSendLink;

  /// Recover error when Firebase returns user-not-found or invalid-email — tells the user this email isn't linked to any Rihla account.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find a Rihla account with this email. Make sure you linked it on your previous device first.'**
  String get authErrorAccountNotFound;

  /// Auth error for Firebase's too-many-requests code.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a few minutes and try again.'**
  String get authErrorRateLimited;

  /// Auth error for Firebase's network-request-failed code.
  ///
  /// In en, this message translates to:
  /// **'No connection. Check your internet and try again.'**
  String get authErrorOffline;

  /// Fallback auth error with the FirebaseAuthException code surfaced for support purposes.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong ({code}). Please try again.'**
  String authErrorGeneric(Object code);

  /// Friendly cause phrase (#356) for offline / unavailable / timed-out errors. Slots into action-context templates like groupFailedLeave.
  ///
  /// In en, this message translates to:
  /// **'Please check your connection and try again.'**
  String get errorNetwork;

  /// Friendly cause phrase (#356) for permission-denied / unauthenticated errors.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to do that.'**
  String get errorPermissionDenied;

  /// Friendly cause phrase (#356) for rate-limit / quota errors (too-many-requests, resource-exhausted).
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a moment and try again.'**
  String get errorTooManyRequests;

  /// Friendly cause phrase (#356) for any unclassified error; the raw detail is sent to Sentry, not shown.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorUnexpected;

  /// Global SnackBar shown when a queued-offline write is rejected by the server on replay after reconnect — the optimistic local change has been rolled back. {cause} is a friendly cause phrase (errorNetwork / errorPermissionDenied / ...).
  ///
  /// In en, this message translates to:
  /// **'A recent change couldn\'t be saved: {cause}'**
  String lateWriteFailedNotice(Object cause);

  /// Shown on the Link-email screen when the email is already linked to another Rihla account.
  ///
  /// In en, this message translates to:
  /// **'This email is already linked to a Rihla account. Restore from that account instead.'**
  String get authErrorEmailAlreadyLinked;

  /// Shown on the Link-email screen when Firebase rejects the email format.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a valid email.'**
  String get authErrorInvalidEmail;

  /// Form-validator error on the Link-email screen when the email and confirm-email fields disagree.
  ///
  /// In en, this message translates to:
  /// **'Emails don\'t match.'**
  String get authErrorEmailsDontMatch;

  /// App bar title on the Link-email screen (Settings → Linked email → Set up).
  ///
  /// In en, this message translates to:
  /// **'Link your email'**
  String get authLinkEmailTitle;

  /// Headline on the Link-email screen — frames email-link as a recovery anchor, not a login.
  ///
  /// In en, this message translates to:
  /// **'So you can come back'**
  String get authLinkEmailHeading;

  /// Body copy under the headline on the Link-email screen explaining the recovery promise.
  ///
  /// In en, this message translates to:
  /// **'We\'ll email you a one-tap sign-in link. If you ever lose your phone or clear app data, enter the same email on a new device to get all your trips back.'**
  String get authLinkEmailDescription;

  /// Label for the second 'confirm email' text field on the Link-email screen — typo guard.
  ///
  /// In en, this message translates to:
  /// **'Confirm email'**
  String get authLinkEmailConfirmLabel;

  /// Primary CTA on the Link-email screen — sends the sign-in link.
  ///
  /// In en, this message translates to:
  /// **'Send link'**
  String get authLinkEmailSubmit;

  /// Trust note shown below the email fields on the Link-email screen.
  ///
  /// In en, this message translates to:
  /// **'Your email is used only to restore your Rihla data. We don\'t send marketing email and we don\'t share it.'**
  String get authLinkEmailPrivacyNote;

  /// Headline on the recovery-pending screen ('we sent you an email, click the link').
  ///
  /// In en, this message translates to:
  /// **'Check your inbox'**
  String get authRecoverPendingTitle;

  /// First half of the recovery-pending body — split so the user's email can be rendered in a stronger style between prefix and suffix.
  ///
  /// In en, this message translates to:
  /// **'We sent a sign-in link to '**
  String get authRecoverPendingDescriptionPrefix;

  /// Second half of the recovery-pending body, rendered after the user's email.
  ///
  /// In en, this message translates to:
  /// **'. Tap it on this device — we\'ll pull your trips back automatically.'**
  String get authRecoverPendingDescriptionSuffix;

  /// Second half of the link-email-sent body, rendered after the user's email — recovery and link flows share the same prefix but diverge here (link flow finishes the linking; recovery pulls trips back).
  ///
  /// In en, this message translates to:
  /// **'. Tap it on this device to finish linking.'**
  String get authLinkEmailSentDescriptionSuffix;

  /// Helper text on the recovery-pending screen reminding the user to check spam and noting the 24h expiry.
  ///
  /// In en, this message translates to:
  /// **'Can\'t find it? Check your spam folder. The link is good for 24 hours.'**
  String get authRecoverPendingSpamHint;

  /// Inline status shown when the deep-link bootstrap has captured the recovery link and is completing recovery.
  ///
  /// In en, this message translates to:
  /// **'We saw your link. Hang tight — restoring now.'**
  String get authRecoverPendingLinkSeen;

  /// Confirmation status shown after the user successfully resends the recovery link.
  ///
  /// In en, this message translates to:
  /// **'New link sent.'**
  String get authRecoverPendingResendStatus;

  /// Resend error on the recovery-pending screen when Firebase surfaces a specific error code.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t resend ({code}).'**
  String authRecoverPendingResendErrorCode(Object code);

  /// Resend error on the recovery-pending screen for unknown/non-Firebase failures.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t resend. Try again in a bit.'**
  String get authRecoverPendingResendErrorGeneric;

  /// Outlined button label on the recovery-pending screen — resend the email when the cooldown is up.
  ///
  /// In en, this message translates to:
  /// **'Resend link'**
  String get authRecoverPendingResendLink;

  /// Cooldown variant of the resend button label — counts down seconds until resend is allowed.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String authRecoverPendingResendCountdown(int seconds);

  /// #841 PR-3: snack shown when an email-link deep link arrives but no pending email is saved locally (different device, or Settings never primed).
  ///
  /// In en, this message translates to:
  /// **'Open Rihla from the device where you requested the email, or enter the email again here.'**
  String get authEmailLinkNoPendingEmail;

  /// #841 PR-3: snack shown when a recover deep link is blocked because the outgoing anon shell is not provably empty (#647).
  ///
  /// In en, this message translates to:
  /// **'Recovery would switch to your saved account and leave this device\'s current trips behind — they\'re tied to a temporary identity that can\'t be moved. Resolve them first.'**
  String get authEmailLinkRecoverBlocked;

  /// #841 PR-3: success snack shown after an email-link RECOVER swap completes.
  ///
  /// In en, this message translates to:
  /// **'Restored {email}'**
  String authEmailLinkRestored(String email);

  /// #841 PR-3: success snack shown after an email-link LINK completes.
  ///
  /// In en, this message translates to:
  /// **'Linked {email}'**
  String authEmailLinkLinked(String email);

  /// #841 PR-3: catch-all snack shown when completing the email link fails for a non-FirebaseAuthException reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t complete the email link. Try again.'**
  String get authEmailLinkGenericError;

  /// #841 PR-3: humanized auth error for Firebase's invalid-action-code/expired-action-code when completing an email link.
  ///
  /// In en, this message translates to:
  /// **'This link has expired or was already used. Send a new one.'**
  String get authEmailLinkErrorExpired;

  /// #841 PR-3: humanized auth error for Firebase's invalid-email code when completing an email link.
  ///
  /// In en, this message translates to:
  /// **'That email doesn\'t look valid.'**
  String get authEmailLinkErrorInvalidEmail;

  /// #841 PR-3: humanized auth error for Firebase's user-disabled code when completing an email link.
  ///
  /// In en, this message translates to:
  /// **'This account has been disabled.'**
  String get authEmailLinkErrorDisabled;

  /// #841 PR-3: humanized auth error for Firebase's network-request-failed code when completing an email link.
  ///
  /// In en, this message translates to:
  /// **'No connection. Try again when you\'re online.'**
  String get authEmailLinkErrorNetwork;

  /// #841 PR-3: humanized auth error for Firebase's too-many-requests code when completing an email link.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a few minutes and try again.'**
  String get authEmailLinkErrorTooManyRequests;

  /// #841 PR-3: humanized auth error for Firebase's email-already-in-use/credential-already-in-use/provider-already-linked codes when completing an email link.
  ///
  /// In en, this message translates to:
  /// **'This email is already linked to a Rihla account. Restore from that account instead.'**
  String get authEmailLinkErrorAlreadyInUse;

  /// #841 PR-3: fallback humanized auth error surfacing the raw Firebase error code when completing an email link.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong ({code}). Please try again.'**
  String authEmailLinkErrorGeneric(String code);

  /// Boot-time snack shown after a Google/email restore whose swap survived the restart AND (#839) either has data or the presence probe was inconclusive.
  ///
  /// In en, this message translates to:
  /// **'Account restored.'**
  String get recoveryRestoredOk;

  /// #839 boot-time snack shown when the restore's swap survived the restart but a Source.server presence probe SERVER-CONFIRMS the account holds zero groups — points at the existing Profile → Account → Sign out escape path rather than claiming a confident, possibly-wrong success.
  ///
  /// In en, this message translates to:
  /// **'Signed in, but this account has no groups yet. Restored the wrong account? Profile → Account → Sign out lets you try another.'**
  String get recoveryRestoredEmpty;

  /// Boot-time snack shown when a success marker's expectedUid (#458) does not match who is actually signed in after the restart — the swap did not durably survive.
  ///
  /// In en, this message translates to:
  /// **'Account restore didn\'t complete. Please try again.'**
  String get recoverySwapIncomplete;

  /// Empty-state title on the group settle-up screen when the group can no longer be loaded (e.g. the user was removed).
  ///
  /// In en, this message translates to:
  /// **'This group is no longer available'**
  String get groupSettleUpMissingTitle;

  /// Empty-state body on the group settle-up screen when the group is unavailable.
  ///
  /// In en, this message translates to:
  /// **'You may have been removed. Tap below to go back home.'**
  String get groupSettleUpMissingMessage;

  /// Fallback label for a per-event breakdown row when the event's display name is unknown — shows the tail of the event ID.
  ///
  /// In en, this message translates to:
  /// **'Event ...{suffix}'**
  String groupSettleUpEventLabelFallback(Object suffix);

  /// Label for the residual row in a group settle-up per-event breakdown — the cross-event portion of the transfer that isn't attributable to a single event (#752).
  ///
  /// In en, this message translates to:
  /// **'Across events'**
  String get groupSettleUpAcrossEventsLabel;

  /// Fallback errorBuilder text shown by GoRouter when the requested location does not match any route.
  ///
  /// In en, this message translates to:
  /// **'Page not found: {location}'**
  String errorPageNotFound(Object location);

  /// Title on the friendly 404 screen shown by GoRouter's errorBuilder when the requested location does not match any route — e.g. a broken or expired share link.
  ///
  /// In en, this message translates to:
  /// **'Page not found'**
  String get errorPageNotFoundTitle;

  /// Body copy on the friendly 404 screen shown by GoRouter's errorBuilder. The Go Home action label reuses commonGoHome.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted, or the link is incorrect.'**
  String get errorPageNotFoundBody;

  /// Brand tagline shown under the Rihla wordmark on the boot splash screen.
  ///
  /// In en, this message translates to:
  /// **'your shared journey'**
  String get splashTagline;

  /// Title on the splash error state shown when the app fails to start.
  ///
  /// In en, this message translates to:
  /// **'Something\'s off'**
  String get splashErrorTitle;

  /// Body copy on the splash error state shown when the app fails to start.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t start the app.'**
  String get splashErrorBody;

  /// Retry button on the splash error state.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get splashRetry;

  /// Title on the splash error state shown when the first-ever boot auth call fails because the device has no network connection (#838).
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get splashOfflineTitle;

  /// Body copy on the splash error state shown when the first-ever boot auth call fails because the device has no network connection (#838).
  ///
  /// In en, this message translates to:
  /// **'Rihla needs an internet connection the first time it starts. Connect and try again.'**
  String get splashOfflineBody;

  /// Title of the soft in-app rationale sheet shown before the OS push-permission dialog (#352), at the first natural moment (a successful group join or create).
  ///
  /// In en, this message translates to:
  /// **'Stay in the loop'**
  String get notificationRationaleTitle;

  /// Body copy of the notification rationale sheet (#352) — explains the value of push notifications before the OS prompt.
  ///
  /// In en, this message translates to:
  /// **'Get notified when someone adds an expense or settles up.'**
  String get notificationRationaleBody;

  /// Dismiss action on the notification rationale sheet (#352). Declining never re-asks; it does NOT open the OS permission dialog.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notificationRationaleNotNow;

  /// Opt-in action on the notification rationale sheet (#352). Proceeds to the OS permission dialog.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get notificationRationaleTurnOn;

  /// Title of the optional durable-credential sheet (#441/#818). Shown from account-link prompts while the user is still anonymous.
  ///
  /// In en, this message translates to:
  /// **'Keep your money safe'**
  String get durableGateTitle;

  /// Body of the optional durable-credential sheet (#441/#818).
  ///
  /// In en, this message translates to:
  /// **'Your groups and expenses are tied to this account. Link Google so they can\'t be lost with this device.'**
  String get durableGateBody;

  /// Primary action on the optional account-link sheet — opens the Google Credential Manager sheet and links the credential to the current anonymous user.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get durableGateContinueGoogle;

  /// Dismiss action on the durable-credential sheet (#285 backup nudge / manual link entry points). Purely dismisses the sheet — no pending create/join is aborted by it (#818 removed the create-time gate).
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get durableGateNotNow;

  /// Dead-end conflict copy, shown only when the switch offer is unsafe (this device's current account already has groups, or the group check failed). The sheet must never resolve a conflict by signing out.
  ///
  /// In en, this message translates to:
  /// **'That Google account already belongs to another Rihla account. Switching to it would leave this phone\'s current groups behind — they\'re tied to a temporary identity that can\'t be moved. Resolve them first, then use a different Google account.'**
  String get durableGateConflict;

  /// Title of the optional account-link sheet's conflict state (#428): the chosen Google account already backs another Rihla account.
  ///
  /// In en, this message translates to:
  /// **'That account already has Rihla data'**
  String get durableGateConflictTitle;

  /// Body of the conflict switch offer. Only shown when the current anonymous shell is provably empty (zero groups), so switching discards nothing.
  ///
  /// In en, this message translates to:
  /// **'This Google account already has Rihla data. Switch to it? This device will continue with that account.'**
  String get durableGateConflictSwitchBody;

  /// Primary action in the conflict state: discard the empty anonymous shell and sign into the existing Google-backed account (restarts the app).
  ///
  /// In en, this message translates to:
  /// **'Switch account'**
  String get durableGateSwitch;

  /// Secondary action in the conflict state: back to the initial gate sheet to retry with another Google account.
  ///
  /// In en, this message translates to:
  /// **'Use a different account'**
  String get durableGateUseDifferent;

  /// Generic failure line on the gate sheet (config missing, unexpected errors).
  ///
  /// In en, this message translates to:
  /// **'Could not link your account. Try again.'**
  String get durableGateError;

  /// Label for the optional #278 chips field on the create-group screen — add placeholder ('shadow') members by name now, or invite them later.
  ///
  /// In en, this message translates to:
  /// **'Who\'s in?'**
  String get createGroupWhoElse;

  /// Hint inside the #278 add-by-name input; submitting a name turns it into a removable shadow chip.
  ///
  /// In en, this message translates to:
  /// **'Type a name…'**
  String get createGroupAddNameHint;

  /// Shown under the #278 chips field while offline — adding placeholder members needs the addShadowMember callable, which has no offline replay. The group still creates with just the creator.
  ///
  /// In en, this message translates to:
  /// **'Connect to add names'**
  String get createGroupShadowOfflineHint;

  /// #818: shown instead of the offline hint / creator explanation when the current (anonymous) creator has no durable credential — addShadowMember hard-rejects anonymous callers server-side. Reused on the create-screen chips field and the group-settings members section footer.
  ///
  /// In en, this message translates to:
  /// **'Link your account to add people by name — anyone can still join with the invite code.'**
  String get shadowAddRequiresLink;

  /// Snackbar when a seeded placeholder name (#278) collides with an existing member; the group is already created and the other names still proceed.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is already used in this group.'**
  String createGroupShadowNameTaken(Object name);

  /// Snackbar when one or more create-time placeholder names failed after the group itself was created (#649).
  ///
  /// In en, this message translates to:
  /// **'Some names could not be added. You can add them from the group later.'**
  String get createGroupShadowAddFailed;

  /// Title of the #278 PR9 claim picker shown on the join screen when the entered invite code has unclaimed placeholder ('shadow') members.
  ///
  /// In en, this message translates to:
  /// **'Is one of these you?'**
  String get groupClaimPickerTitle;

  /// Subtitle under the #278 PR9 claim picker explaining that tapping a name claims that placeholder member's expenses.
  ///
  /// In en, this message translates to:
  /// **'Someone added these names before you joined. Claim your spot to inherit your share.'**
  String get groupClaimPickerSubtitle;

  /// Action on the #278 PR9 claim picker to skip claiming and join as a brand-new member instead.
  ///
  /// In en, this message translates to:
  /// **'No, I\'m new'**
  String get groupClaimImNew;

  /// Title of the #278 PR9 hard permanent-confirmation sheet; {name} is the placeholder member's name being claimed.
  ///
  /// In en, this message translates to:
  /// **'Claim {name}\'s spot?'**
  String groupClaimConfirmTitle(Object name);

  /// The irreversible-by-design warning body (#278 PR9 D3) on the claim confirmation sheet; {name} is the placeholder member's name.
  ///
  /// In en, this message translates to:
  /// **'This permanently merges {name}\'s expenses into your account. It can\'t be undone, and the group creator must approve.'**
  String groupClaimConfirmWarning(Object name);

  /// Affirmative destructive button on the #278 PR9 permanent-confirmation sheet (requires an explicit tap); {name} is the placeholder member's name.
  ///
  /// In en, this message translates to:
  /// **'Yes, claim {name}\'s spot'**
  String groupClaimConfirmCta(Object name);

  /// Title of the #278 PR9 waiting state after a claim request is sent, before the creator approves.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval'**
  String get groupClaimWaitingTitle;

  /// Body of the #278 PR9 waiting state; {name} is the claimed placeholder member's name.
  ///
  /// In en, this message translates to:
  /// **'We sent your request to the group creator. You\'ll join {name}\'s spot once they approve.'**
  String groupClaimWaitingBody(Object name);

  /// Button on the #278 PR9 waiting state to re-poll whether the creator has approved the claim.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get groupClaimCheckAgain;

  /// Snackbar on the #278 PR9 waiting state when a re-check finds the claim is still pending.
  ///
  /// In en, this message translates to:
  /// **'Still waiting for the creator to approve.'**
  String get groupClaimStillPending;

  /// Shown on the #278 PR9 waiting state when the creator declined the claim request.
  ///
  /// In en, this message translates to:
  /// **'The creator declined your claim. You can join as a new member instead.'**
  String get groupClaimDeclinedBody;

  /// Error on the #278 PR9 join screen when a brand-new join name collides with an existing (possibly shadow) member — the user should claim it via the picker or pick another name.
  ///
  /// In en, this message translates to:
  /// **'That name belongs to someone added earlier. Claim it above, or pick a different name.'**
  String get groupClaimNameTakenClaimInstead;

  /// Header of the #278 PR9 creator-only section in group settings listing pending placeholder-claim requests.
  ///
  /// In en, this message translates to:
  /// **'Claim requests'**
  String get groupClaimRequestsTitle;

  /// One pending claim-request row in the #278 PR9 creator section; {requester} is the asking person's name, {shadow} the placeholder member's name.
  ///
  /// In en, this message translates to:
  /// **'{requester} wants to claim {shadow}\'s spot'**
  String groupClaimRequestRow(Object requester, Object shadow);

  /// Consequence line on the #278 A6 claim-approval card spelling out the irreversible balance merge; {shadow} is the placeholder's name, {requester} the joining person's name.
  ///
  /// In en, this message translates to:
  /// **'Approving merges {shadow}\'s expenses into {requester}. This can\'t be undone.'**
  String groupClaimMergeConsequence(Object shadow, Object requester);

  /// Small pill badge on a #278 A6 claim-request card marking the request as awaiting the creator's decision.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get groupClaimPendingBadge;

  /// Button to approve a #278 PR9 claim request (runs the merge that gives the requester the placeholder's balance).
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get groupClaimApprove;

  /// Button to decline a #278 PR9 claim request.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get groupClaimDecline;

  /// Success snackbar after a #278 PR9 claim is approved; {requester} is the new member's name, {shadow} the placeholder's name.
  ///
  /// In en, this message translates to:
  /// **'{requester} now holds {shadow}\'s spot.'**
  String groupClaimApproved(Object requester, Object shadow);

  /// Snackbar after the creator declines a #278 PR9 claim request.
  ///
  /// In en, this message translates to:
  /// **'Request declined.'**
  String get groupClaimRequestDeclined;

  /// Snackbar when a #278 PR9 claim approval fails with a retryable (internal) error; the creator can try approving again.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t complete the claim. Try again.'**
  String get groupClaimApproveError;

  /// Quiet empty-state for the #278 PR9 creator claim-requests section when there are none.
  ///
  /// In en, this message translates to:
  /// **'No pending claim requests.'**
  String get groupClaimNoRequests;

  /// #811: lead text on the open-event recap banner — the labelled entry that replaced the tooltip-only header cup. Paired with the eventViewReceipt "View recap" action on the same bar.
  ///
  /// In en, this message translates to:
  /// **'See the trip so far'**
  String get recapOpenBannerLead;

  /// Subtitle under the recap title showing participant and expense counts (#202).
  ///
  /// In en, this message translates to:
  /// **'{people, plural, =1{1 person} other{{people} people}} · {expenses, plural, =1{1 expense} other{{expenses} expenses}}'**
  String recapPeopleExpenses(int people, int expenses);

  /// Section label for total event spend in the recap (#202).
  ///
  /// In en, this message translates to:
  /// **'Total spent'**
  String get recapTotalSpent;

  /// Caption under the recap title once an event is closed and its spending snapshot is captured; settlement stays live (#766).
  ///
  /// In en, this message translates to:
  /// **'Spending frozen · closed {date}'**
  String recapSpendingFrozen(String date);

  /// Dateless variant of recapSpendingFrozen for the brief window where closedAt (a server timestamp) has not resolved yet (#766).
  ///
  /// In en, this message translates to:
  /// **'Spending frozen'**
  String get recapSpendingFrozenNoDate;

  /// Section label for the current user's money summary in the recap (#202).
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get recapYouTitle;

  /// Row label: amount the current user paid into event expenses (#202).
  ///
  /// In en, this message translates to:
  /// **'You paid'**
  String get recapYouPaid;

  /// Row label: the current user's owed share of event expenses (#202).
  ///
  /// In en, this message translates to:
  /// **'Your share'**
  String get recapYourShare;

  /// Row label: the current user's net settlements; positive = given, negative = received (#202).
  ///
  /// In en, this message translates to:
  /// **'Settlements'**
  String get recapSettlements;

  /// Row label: the current user's net balance for the event (#202).
  ///
  /// In en, this message translates to:
  /// **'Net'**
  String get recapNet;

  /// Empty-state title when an event has no expenses to recap (#202).
  ///
  /// In en, this message translates to:
  /// **'Nothing to wrap up yet'**
  String get recapEmptyTitle;

  /// Empty-state body when an event has no expenses to recap (#202).
  ///
  /// In en, this message translates to:
  /// **'Add an expense to see this event\'s recap.'**
  String get recapEmptyMessage;

  /// Highlight-card label for the person who fronted the most cash in the event recap (#721).
  ///
  /// In en, this message translates to:
  /// **'Top payer'**
  String get recapTopPayer;

  /// Highlight-card label for the single largest expense in the event recap (#721).
  ///
  /// In en, this message translates to:
  /// **'Biggest expense'**
  String get recapBiggestExpense;

  /// Section label above the per-category spend breakdown in the recap (#721).
  ///
  /// In en, this message translates to:
  /// **'By category'**
  String get recapByCategory;

  /// Section label above the per-payer gross-spend breakdown in the recap (#721).
  ///
  /// In en, this message translates to:
  /// **'Who paid'**
  String get recapWhoPaid;

  /// Section label above the per-person net-balance list in the recap (#721).
  ///
  /// In en, this message translates to:
  /// **'Who\'s up / down'**
  String get recapWhoUpDown;

  /// Quiet trailing label on a recap net row when that person's balance is exactly zero (#721).
  ///
  /// In en, this message translates to:
  /// **'settled'**
  String get recapSettledRow;

  /// Suffix marking the current user's own row in recap lists, rendered as 'Name · you' (#721).
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get recapYouSuffix;

  /// Title of the recap settlement-status card when no balances are outstanding (#721).
  ///
  /// In en, this message translates to:
  /// **'Everyone\'s settled up'**
  String get recapSettledTitle;

  /// Subtitle of the recap settlement-status card when everyone is settled (#721).
  ///
  /// In en, this message translates to:
  /// **'No outstanding balances in this event.'**
  String get recapSettledSubtitle;

  /// Title of the recap settlement-status card when balances remain unsettled (#721).
  ///
  /// In en, this message translates to:
  /// **'Outstanding balances'**
  String get recapOutstandingTitle;

  /// Subtitle of the recap settlement-status card; {count} is the number of people who still owe (debtors only) (#721).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 person still owes} other{{count} people still owe}}.'**
  String recapOutstandingSubtitle(int count);

  /// Title of the actionable settle-up CTA on the event recap screen, shown when balances are outstanding (#721).
  ///
  /// In en, this message translates to:
  /// **'Ready to settle up?'**
  String get recapSettleCtaTitle;

  /// Explains the difference between event-level and group-level settlement on the recap CTA (#721).
  ///
  /// In en, this message translates to:
  /// **'Settle just this event, or net your balances across the whole group.'**
  String get recapSettleCtaBody;

  /// Primary button on the recap settle CTA — opens event-level settle-up (#721).
  ///
  /// In en, this message translates to:
  /// **'Settle this event'**
  String get recapSettleThisEvent;

  /// Secondary button on the recap settle CTA — opens group-level settle-up (#721).
  ///
  /// In en, this message translates to:
  /// **'Settle at group level'**
  String get recapSettleAtGroup;

  /// Note shown under the total-spent card when an event spans more than one currency, explaining buckets are never cross-summed (#721).
  ///
  /// In en, this message translates to:
  /// **'Balances are kept per currency — they\'re never added together.'**
  String get recapMultiCurrencyNote;

  /// Tooltip/label for the share action on the recap screen that opens the shareable card (#722).
  ///
  /// In en, this message translates to:
  /// **'Share recap'**
  String get recapShareButton;

  /// Primary button in the recap share preview sheet that exports + shares the card as a PNG (#722).
  ///
  /// In en, this message translates to:
  /// **'Share image'**
  String get recapShareCta;

  /// Secondary button in the recap share sheet that exports the full Trip Receipt proof pack (expenses, allocations, settlements, corrections, balances) as a CSV file (#704).
  ///
  /// In en, this message translates to:
  /// **'Export ledger (CSV)'**
  String get recapExportCsvButton;

  /// Secondary button in the recap share sheet that exports the full Trip Receipt proof pack (expenses, allocations, settlements, corrections, balances) as a formatted PDF document (#704 Slice B).
  ///
  /// In en, this message translates to:
  /// **'Export ledger (PDF)'**
  String get recapExportPdfButton;

  /// Snackbar shown when capturing the recap card to a PNG fails (#722).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the image. Please try again.'**
  String get recapShareError;

  /// Caption text that rides along with the shared recap image (#722).
  ///
  /// In en, this message translates to:
  /// **'{eventName} — our trip recap, tracked with Rihla'**
  String recapShareText(String eventName);

  /// Mono caption stamp on the recap share card's cover band; {month} is a localized month + year (#722).
  ///
  /// In en, this message translates to:
  /// **'Rihla · Wrapped · {month}'**
  String recapCardCaption(String month);

  /// Recap share-card cover caption when the event has no dates (#722).
  ///
  /// In en, this message translates to:
  /// **'Rihla · Wrapped'**
  String get recapCardCaptionPlain;

  /// Recap share-card stat label for the participant count (#722).
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get recapCardPeople;

  /// Recap share-card stat label for the expense count (#722).
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get recapCardExpenses;

  /// Recap share-card stat label: average spend per day of the trip (#722).
  ///
  /// In en, this message translates to:
  /// **'Avg / day'**
  String get recapCardAvgPerDay;

  /// Recap share-card stat label: spend per person, used when the event has no dates (#722).
  ///
  /// In en, this message translates to:
  /// **'Per person'**
  String get recapCardPerPerson;

  /// Recap share-card label for the person who paid the most (#722).
  ///
  /// In en, this message translates to:
  /// **'Top spender'**
  String get recapCardTopSpender;

  /// Recap share-card label for the single largest expense (#722).
  ///
  /// In en, this message translates to:
  /// **'Biggest splurge'**
  String get recapCardBiggest;

  /// Recap share-card label above the category breakdown bar (#722).
  ///
  /// In en, this message translates to:
  /// **'Where it went'**
  String get recapCardWhereItWent;

  /// Recap share-card status pill when every balance is settled (#722).
  ///
  /// In en, this message translates to:
  /// **'All settled'**
  String get recapCardAllSettled;

  /// Recap share-card status pill when balances are outstanding; {count} is the number of debtors (#722).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 still to settle} other{{count} still to settle}}'**
  String recapCardStillToSettle(int count);

  /// Document-close ritual caption under the recap share card's footer wordmark, and the PDF trip receipt's closing line (Falaj rebrand PR-3 #900).
  ///
  /// In en, this message translates to:
  /// **'recorded in Rihla'**
  String get recapRecordedInRihla;

  /// Global search entry-point semantic label (home top-bar icon) and back-button destination title (#900 friction #3 — PR-5b).
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTitle;

  /// Placeholder text in the global search field. Cold /search (no query) shows this same hint — no separate empty-state panel (PR-5b).
  ///
  /// In en, this message translates to:
  /// **'Search groups and events'**
  String get searchHint;

  /// Global search zero-results state for a non-empty query. STATIC — no {query} placeholder, unlike activitySearchNoMatchesMessage (PR-5b).
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get searchEmpty;

  /// Global search results section header for matched groups (rendered uppercase by SectionHeader, PR-5b).
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get searchSectionGroups;

  /// Global search results section header for matched events, open and closed (rendered uppercase by SectionHeader, PR-5b).
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get searchSectionEvents;

  /// Compact pill on a closed event's search result row — a lifecycle marker (event.isClosed), never the balance-state 'settled' (PR-5b).
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get searchEventEnded;

  /// Rendered scope line above global search results, making the v1 search scope (groups + events, no expenses) honest on screen (PR-5b Gate R2 P1 fix).
  ///
  /// In en, this message translates to:
  /// **'Groups and events, including past events'**
  String get searchScopeLabel;
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
