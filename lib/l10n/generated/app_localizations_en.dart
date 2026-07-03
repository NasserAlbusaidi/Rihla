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
  String get bannerSavedWillSync => 'Saved — will sync';

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
  String get createGroupCurrencyHint =>
      'This group\'s currency. It can\'t be changed later.';

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
  String get editNamePreviewCaption => 'How you\'ll appear in groups';

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
  String get profileSectionDanger => 'DANGER';

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
  String get profileNotificationsErrorHint =>
      'Couldn\'t register — tap to retry';

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
  String get profileBackupStatusNotBackedUp => 'Not backed up';

  @override
  String get profileBackupStatusBackedUp => 'Backed up';

  @override
  String get profileBackupCardTitle => 'Back up this account';

  @override
  String get profileBackupCardBody =>
      'Your trips live only on this phone. Add an email or Google so you never lose them.';

  @override
  String get profileSetYourName => 'Set your name';

  @override
  String get profileHandlePlaceholder => 'no name yet';

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
  String get deleteAccountTitle => 'Delete your account?';

  @override
  String get deleteAccountContent =>
      'This permanently deletes your Rihla account. Your linked email (if any) will be released so it can be reused. Trips, expenses, and balances tied to your account become unreachable. There\'s no undo.';

  @override
  String get deleteAccountConfirm => 'Delete account';

  @override
  String get deleteGuestSessionTitle => 'Delete this guest session?';

  @override
  String get deleteGuestSessionContent =>
      'This deletes only this guest session on this device. Any Google or email account you\'ve linked is separate and is NOT deleted unless you sign in to it first. There\'s no undo.';

  @override
  String get deleteGuestSessionConfirm => 'Delete guest data';

  @override
  String get durableShellDeleteTitle => 'Delete account?';

  @override
  String get durableShellDeleteContent =>
      'A saved account is set up on this device. Deleting now removes only this guest session — your saved account and its data stay. To delete your saved account, sign in to it first using the account options on this screen.';

  @override
  String get durableShellDeleteSignIn => 'Sign in to my account';

  @override
  String get durableShellDeleteGuest => 'Delete just this guest session';

  @override
  String get durableShellDeleteCancel => 'Cancel';

  @override
  String get deleteAccountRetryTitle => 'Deletion didn\'t finish';

  @override
  String get deleteAccountRetryContent =>
      'Some of your account data was removed, but the deletion didn\'t finish. Your account is still signed in. Retrying will complete it.';

  @override
  String get signOutTitle => 'Sign out of this device?';

  @override
  String get signOutContentGoogle =>
      'Your data stays in the cloud. To restore, sign back in with the same Google account.';

  @override
  String get profileAccountGoogle => 'Google account';

  @override
  String get profileAccountGoogleLinked => 'Linked';

  @override
  String get profileAccountLinkGoogle => 'Link Google account';

  @override
  String get signOutContentPrefix =>
      'Your data stays in the cloud. To restore, enter ';

  @override
  String get signOutContentSuffix => ' on any device.';

  @override
  String get signOutConfirm => 'Sign out';

  @override
  String get profileStatsAllTime => 'all-time';

  @override
  String get profileStatsActive => 'active';

  @override
  String get profileStatsLifetime => 'lifetime';

  @override
  String get profileStatsLoadFailed => 'Couldn\'t load your stats';

  @override
  String profileStatsSpentMore(int count) {
    return '+$count';
  }

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

  @override
  String get commonApply => 'Apply';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonBack => 'Back';

  @override
  String get commonClose => 'Close';

  @override
  String get commonGoHome => 'Go Home';

  @override
  String get commonSemanticBackspace => 'Backspace';

  @override
  String get commonSemanticDecimalPoint => 'Decimal point';

  @override
  String get timelineToday => 'Today';

  @override
  String get timelineYesterday => 'Yesterday';

  @override
  String get timelineRangeSeparator => '—';

  @override
  String get ledgerBucketFood => 'Food';

  @override
  String get ledgerBucketLodging => 'Lodging';

  @override
  String get ledgerBucketTransit => 'Transit';

  @override
  String get ledgerBucketGroceries => 'Groceries';

  @override
  String get ledgerBucketActivities => 'Activities';

  @override
  String get ledgerBucketOther => 'Other';

  @override
  String get categoryFood => 'Food';

  @override
  String get categoryTransport => 'Transport';

  @override
  String get categoryAccommodation => 'Accommodation';

  @override
  String get categoryActivities => 'Activities';

  @override
  String get categoryShopping => 'Shopping';

  @override
  String get categoryGroceries => 'Groceries';

  @override
  String get categoryDrinks => 'Drinks';

  @override
  String get categoryFuel => 'Fuel';

  @override
  String get categoryFees => 'Fees';

  @override
  String get categoryOther => 'Other';

  @override
  String get ledgerBackTooltip => 'Back';

  @override
  String get ledgerSearchExpensesTooltip => 'Search expenses';

  @override
  String get ledgerActivityTooltip => 'Activity log';

  @override
  String get ledgerEventSettingsTooltip => 'Event settings';

  @override
  String ledgerPeopleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PEOPLE',
      one: '1 PERSON',
    );
    return '$_temp0';
  }

  @override
  String get ledgerAllFilter => 'All';

  @override
  String get ledgerCategoriesAppear => 'categories appear as you log them';

  @override
  String get ledgerNothingInCategoryTitle => 'Nothing in this category';

  @override
  String get ledgerNothingInCategoryMessage =>
      'Try a different category, or switch back to All.';

  @override
  String get ledgerSettlementsHiddenByCategory =>
      'Settlements aren\'t categorized, so they\'re hidden while filtering.';

  @override
  String get ledgerClearFilters => 'Clear filters';

  @override
  String get ledgerEndOfLedger => 'END OF LEDGER';

  @override
  String get ledgerEmptyStateTitle => 'An empty page, ready to be written.';

  @override
  String ledgerEmptyStateFirstExpenseBody(Object currency) {
    return 'The first $currency you log will set the trip total. We\'ll split it equally between everyone on the trip.';
  }

  @override
  String ledgerEmptyFirstExpenseCamping(Object currency) {
    return 'The first $currency you log will set the camping total. We\'ll split it equally between everyone camping.';
  }

  @override
  String ledgerEmptyFirstExpenseOuting(Object currency) {
    return 'The first $currency you log will set the outing total. We\'ll split it equally between everyone on the outing.';
  }

  @override
  String ledgerEmptyFirstExpenseEvent(Object currency) {
    return 'The first $currency you log will set the event total. We\'ll split it equally between everyone in the group.';
  }

  @override
  String get ledgerCouldNotLoadEventTitle => 'Could not load event';

  @override
  String get ledgerCouldNotLoadLedgerTitle => 'Couldn\'t load ledger';

  @override
  String get ledgerEventNotFoundTitle => 'Event not found';

  @override
  String get ledgerConnectionRetryMessage =>
      'Check your connection and try again.';

  @override
  String get ledgerEventNotFoundMessage =>
      'It may have been deleted, or the link is incorrect.';

  @override
  String get ledgerReload => 'Reload';

  @override
  String get ledgerHeroPositivePrefix => 'You\'re up';

  @override
  String ledgerHeroPositiveTail(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
    );
    return 'across $_temp0.';
  }

  @override
  String get ledgerHeroNegativePrefix => 'You owe';

  @override
  String ledgerHeroNegativeTail(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
    );
    return 'to $_temp0.';
  }

  @override
  String get ledgerHeroEmptyPrefix => 'Nothing logged yet';

  @override
  String get ledgerHeroEmptyTail =>
      'add the first expense and we\'ll start the math.';

  @override
  String get ledgerAllSquare => 'All square.';

  @override
  String get ledgerSettledBadge => 'SETTLED';

  @override
  String get ledgerTripTotal => 'TRIP TOTAL';

  @override
  String ledgerExpenseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count expenses',
      one: '1 expense',
    );
    return '$_temp0';
  }

  @override
  String ledgerSettledCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count settled',
      one: '1 settled',
    );
    return '$_temp0';
  }

  @override
  String get ledgerYou => 'You';

  @override
  String get ledgerEven => 'EVEN';

  @override
  String get ledgerMemberFallback => 'Member';

  @override
  String get ledgerSomeone => 'Someone';

  @override
  String get ledgerSomeoneLower => 'someone';

  @override
  String get ledgerUnknown => 'Unknown';

  @override
  String get ledgerExpenseFallback => 'Expense';

  @override
  String get ledgerSettlementFallback => 'Settlement';

  @override
  String get ledgerSettlementLabel => 'SETTLEMENT';

  @override
  String get ledgerPaidConnector => 'paid';

  @override
  String ledgerPaidBy(Object name) {
    return 'Paid by $name';
  }

  @override
  String ledgerSplitWays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ways',
      one: '1 way',
    );
    return 'split $_temp0';
  }

  @override
  String get ledgerSearchHint => 'Search expenses';

  @override
  String get ledgerSearchTitle => 'Search expenses';

  @override
  String get ledgerSearchPromptMessage =>
      'Type to find by description, category, payer, recipient or note.';

  @override
  String get ledgerSearchNoMatchesTitle => 'No matches';

  @override
  String ledgerSearchNoMatchesMessage(Object query) {
    return 'Nothing in this event matches \"$query\".';
  }

  @override
  String get ledgerRecentExpenses => 'RECENT EXPENSES';

  @override
  String get ledgerRecordedHistory => 'RECORDED HISTORY';

  @override
  String get ledgerPaymentDue => 'PAYMENT DUE';

  @override
  String get ledgerYouAreOwed => 'YOU ARE OWED';

  @override
  String get ledgerYouOwe => 'YOU OWE';

  @override
  String get ledgerTripTotalPending => 'Trip Total Pending';

  @override
  String get ledgerTotalPaidByYou => 'Total Paid by You';

  @override
  String get ledgerGeneralCategory => 'General';

  @override
  String ledgerOwedToYou(Object currency, Object amount) {
    return 'Owed to you $currency $amount';
  }

  @override
  String ledgerYouOweAmount(Object currency, Object amount) {
    return 'You owe $currency $amount';
  }

  @override
  String get ledgerSettled => 'Settled';

  @override
  String ledgerPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
    );
    return '$_temp0';
  }

  @override
  String get ledgerGroup => 'group';

  @override
  String get ledgerAddExpense => 'Add expense';

  @override
  String get ledgerSettleUp => 'Settle up';

  @override
  String get editorTitleAddExpense => 'Add expense';

  @override
  String get editorTitleEditExpense => 'Edit expense';

  @override
  String get editorTitleNewExpense => 'New expense';

  @override
  String get editorActionAdd => 'Add';

  @override
  String get editorActionSave => 'Save';

  @override
  String get editorCategoryPrompt => 'What was this for?';

  @override
  String get editorCategory => 'Category';

  @override
  String get editorCategoryRequired => 'Choose a category';

  @override
  String get editorPaidBy => 'Paid by';

  @override
  String get editorChange => 'Change';

  @override
  String get editorSplitBetween => 'Split between';

  @override
  String get editorHow => 'How';

  @override
  String get editorWhere => 'Where';

  @override
  String get editorCustomise => 'Customise';

  @override
  String editorAmountLabel(Object currency) {
    return 'AMOUNT · $currency';
  }

  @override
  String get editorDescriptionLabel => 'Description';

  @override
  String get editorDescriptionHint => 'What was it for?';

  @override
  String get editorPleaseEnterValidAmount => 'Please enter a valid amount';

  @override
  String get editorAmountGreaterThanZero => 'Amount must be greater than zero';

  @override
  String get editorAmountTooLarge => 'Amount is too large.';

  @override
  String get editorExactSplitOutOfSync =>
      'The exact amounts no longer add up to the total. Reopen the split to update them.';

  @override
  String get editorCouldNotIdentifyParticipant =>
      'Could not identify your participant record.';

  @override
  String editorFailedToAddExpense(String error) {
    return 'Failed to add expense: $error';
  }

  @override
  String editorFailedToUpdateExpense(String error) {
    return 'Failed to update expense: $error';
  }

  @override
  String get editorDeleteExpenseTitle => 'Delete expense?';

  @override
  String get editorDeleteExpenseBody =>
      'Removing it updates everyone\'s balances for this event.';

  @override
  String editorDeleteExpenseFailed(Object error) {
    return 'Failed to delete expense: $error';
  }

  @override
  String get editorPickAtLeastTwoPeople =>
      'Pick at least two people in \"Split between\" first.';

  @override
  String get editorCouldNotLoadCategories => 'Could not load categories.';

  @override
  String get editorMemberFallback => 'Member';

  @override
  String get editorPaidRole => 'Paid';

  @override
  String get editorSelectedPayer => 'Selected payer';

  @override
  String get editorSelectedPaidFullAmount => 'Selected · paid the full amount';

  @override
  String editorProvenanceAdded(Object name) {
    return 'Added by $name';
  }

  @override
  String editorProvenanceAddedEdited(Object creator, Object editor) {
    return 'Added by $creator · edited by $editor';
  }

  @override
  String get editorEventDefault => 'EVENT DEFAULT';

  @override
  String get editorTapCustomiseSplit =>
      'Tap Customise to pick who splits this.';

  @override
  String editorSplitSummary(Object scope, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ways',
      one: '1 way',
    );
    return '$scope · $_temp0';
  }

  @override
  String editorEachAmount(Object amount) {
    return '$amount each';
  }

  @override
  String editorCurrencyMismatch(Object selected, Object dominant) {
    return 'This expense is in $selected, but this event mostly uses $dominant.';
  }

  @override
  String get editorPickAtLeastTwoToSplit =>
      'Pick at least two people to split.';

  @override
  String editorSplitEvenly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ways',
      one: '1 way',
    );
    return 'Split evenly across $_temp0.';
  }

  @override
  String get editorWeightedByShares => 'Weighted by shares.';

  @override
  String get editorPerPersonAmounts => 'Per-person amounts.';

  @override
  String get editorPerPersonPercents => 'Per-person percents.';

  @override
  String get editorAmountsVary => 'Amounts vary per person.';

  @override
  String get editorEvent => 'Event';

  @override
  String get editorDate => 'Date';

  @override
  String get editorDeleteThisExpense => 'Delete this expense';

  @override
  String get editorDeleteThisExpenseBody =>
      'Removes for everyone in this event.';

  @override
  String get editorDiscardAddTitle => 'Discard this expense?';

  @override
  String get editorDiscardEditTitle => 'Discard your changes?';

  @override
  String get editorDiscardBody => 'You\'ll lose what you\'ve entered.';

  @override
  String get editorDiscardKeepEditing => 'Keep editing';

  @override
  String get editorDiscardConfirm => 'Discard';

  @override
  String get editorCustomiseSplit => 'Customise split';

  @override
  String get editorSelectParticipants => 'SELECT PARTICIPANTS';

  @override
  String editorSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String get editorUnableToLoadParticipants => 'Unable to load participants';

  @override
  String get editorNoOtherParticipants => 'No other participants to select';

  @override
  String get editorUnknownParticipant => 'Unknown';

  @override
  String get editorShadowProfile => 'Hasn\'t joined yet';

  @override
  String get editorPaidByLabel => 'PAID BY';

  @override
  String editorParticipantMe(Object name) {
    return '$name (Me)';
  }

  @override
  String get editorCouldNotLoadExpenseTitle => 'Could not load expense';

  @override
  String get editorCouldNotLoadExpenseMessage =>
      'Something went wrong. Try again in a moment.';

  @override
  String get editorExpenseNotFoundTitle => 'Expense not found';

  @override
  String get editorExpenseNotFoundMessage =>
      'This expense may have been deleted.';

  @override
  String get editorViewOnlyTitle => 'View only';

  @override
  String get editorViewOnlyMessage =>
      'Only people in this event can edit expenses.';

  @override
  String get editorExpenseDeleted => 'Expense deleted';

  @override
  String get editorScopeGlobal => 'Everyone';

  @override
  String get editorScopeSubGroup => 'Group split';

  @override
  String get editorScopeCustom => 'Some people';

  @override
  String get editorScopePersonal => 'Just me';

  @override
  String get editorSplit => 'Split';

  @override
  String get editorWhoSplits => 'Who splits';

  @override
  String get editorSplitModeExactShort => 'Exact';

  @override
  String get editorSplitModePercentShort => '%';

  @override
  String editorSplitAddsUpTo(String amount) {
    return 'Adds up to $amount';
  }

  @override
  String get editorReceiptOptional => 'RECEIPT (OPTIONAL)';

  @override
  String get editorReceiptUploading => 'Uploading receipt...';

  @override
  String get editorReceiptAttached => 'Receipt attached';

  @override
  String get editorReceiptTapToChange => 'Tap to change';

  @override
  String get editorReceiptAddPhoto => 'Add a receipt photo';

  @override
  String get customSplitTitle => 'Customise split';

  @override
  String get customSplitCancel => 'Cancel';

  @override
  String get customSplitApply => 'Apply';

  @override
  String get customSplitHow => 'Split how?';

  @override
  String get customSplitTotal => 'TOTAL';

  @override
  String get customSplitModeEqually => 'Equally';

  @override
  String get customSplitModeShares => 'Shares';

  @override
  String get customSplitModeExact => 'Exact';

  @override
  String get customSplitModePercent => 'Percent';

  @override
  String get editorSplitItemized => 'Itemized';

  @override
  String get splitModeHelpEqually => 'Everyone pays the same.';

  @override
  String get splitModeHelpShares =>
      'Weight who owes more — e.g. couples or big eaters.';

  @override
  String get splitModeHelpExact => 'Type each person\'s exact share.';

  @override
  String get splitModeHelpPercent => 'Split by percentage of the total.';

  @override
  String get splitModeHelpItemized =>
      'Add each receipt line and tick who ordered it.';

  @override
  String get itemizedItemsHeader => 'Items';

  @override
  String get itemizedAddItem => '+ Add item';

  @override
  String get itemizedRemoveItem => 'Remove item';

  @override
  String get itemizedItemLabelHint => 'Item';

  @override
  String get itemizedWhoHadThis => 'Who had this?';

  @override
  String get itemizedEveryone => 'Everyone';

  @override
  String get itemizedEachOwes => 'Each person owes';

  @override
  String get itemizedItemsMatchTotal => 'Items match total';

  @override
  String itemizedAmountLeft(Object amount) {
    return '$amount left';
  }

  @override
  String itemizedForName(Object name) {
    return 'for $name';
  }

  @override
  String itemizedNItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get itemizedNeedsSomeone => 'Assign someone';

  @override
  String get adjustmentsHeader => 'Adjustments';

  @override
  String get adjustmentAddAction => '+ Add';

  @override
  String get adjustmentRemove => 'Remove adjustment';

  @override
  String get adjustmentSheetTitle => 'Add adjustment';

  @override
  String get adjustmentTypeService => 'Service';

  @override
  String get adjustmentTypeTax => 'Tax';

  @override
  String get adjustmentTypeTip => 'Tip';

  @override
  String get adjustmentTypeDiscount => 'Discount';

  @override
  String get adjustmentAmountLabel => 'Amount';

  @override
  String get adjustmentSpreadHeader => 'How to spread it';

  @override
  String get adjustmentAllocEqual => 'Split equally';

  @override
  String get adjustmentAllocProportional => 'By item share';

  @override
  String get adjustmentDiscountNote =>
      'A discount is shared in proportion to what each person owes.';

  @override
  String get adjustmentDone => 'Done';

  @override
  String get categoryPickerTitle => 'What\'s this for?';

  @override
  String get categoryPickerCouldNotLoad => 'Could not load categories.';

  @override
  String get categoryPickerRestaurantsBarsCafes => 'Restaurants, bars, cafes';

  @override
  String get categoryPickerHotelsRentals => 'Hotels, rentals';

  @override
  String get categoryPickerTaxiTrainFuel => 'Taxi, train, fuel';

  @override
  String get categoryPickerMarketsSupplies => 'Markets, supplies';

  @override
  String get categoryPickerToursTickets => 'Tours, tickets';

  @override
  String get categoryPickerPetrolCharging => 'Petrol, charging';

  @override
  String get categoryPickerEquipmentSupplies => 'Equipment, supplies';

  @override
  String get categoryPickerAnythingElse => 'Anything else';

  @override
  String get settleUpTitle => 'Settle Up';

  @override
  String get settleUpEventMissingTitle => 'This event no longer exists';

  @override
  String get settleUpEventMissingMessage =>
      'It may have been deleted. Tap below to go back to your groups.';

  @override
  String get settleUpCouldNotLoadBalances => 'Couldn\'t load balances.';

  @override
  String get settleUpIncompleteBalanceWarning =>
      'This balance may be incomplete — some event data couldn\'t be loaded.';

  @override
  String get settleUpAmountGreaterThanZero =>
      'Amount must be greater than zero';

  @override
  String get settleUpEnterValidAmount => 'Please enter a valid amount';

  @override
  String settleUpAmountExceedsOutstanding(Object amount) {
    return 'Amount cannot exceed the outstanding balance of $amount';
  }

  @override
  String settleUpBalanceChangedReviewAgain(Object amount) {
    return 'Balance changed while you were recording — it\'s now $amount. Review and try again.';
  }

  @override
  String get settleUpRecorded => 'Settlement recorded.';

  @override
  String get settleUpRecordedWillSync =>
      'Settlement recorded — will sync when online.';

  @override
  String get settleUpRecordFailed =>
      'Couldn\'t record settlement. Check your connection and try again.';

  @override
  String get settleUpRecordFailedDenied =>
      'This settlement wasn\'t allowed. Please check the details and try again.';

  @override
  String get settleUpRecordFailedGeneric =>
      'Couldn\'t record settlement. Please try again.';

  @override
  String get settleUpCorrect => 'Correct';

  @override
  String get settleUpCorrectTitle => 'Correct this payment?';

  @override
  String settleUpCorrectBody(Object amount, Object recipient, Object payer) {
    return 'This records a reversing payment of $amount from $recipient back to $payer. The original payment stays in your history.';
  }

  @override
  String get settleUpCorrectConfirm => 'Record correction';

  @override
  String get settleUpCorrectionNote => 'Correction of a recorded payment';

  @override
  String get settleUpCorrectionTag => 'Correction';

  @override
  String get preSettleReviewTitle => 'Before you settle';

  @override
  String preSettleReviewExactCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exact splits',
      one: '1 exact split',
    );
    return '$_temp0';
  }

  @override
  String preSettleReviewCustomCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count custom participant splits',
      one: '1 custom participant split',
    );
    return '$_temp0';
  }

  @override
  String preSettleReviewPersonalCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personal expenses',
      one: '1 personal expense',
    );
    return '$_temp0';
  }

  @override
  String preSettleReviewLargeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count large expenses',
      one: '1 large expense',
    );
    return '$_temp0';
  }

  @override
  String preSettleReviewPayerLeftCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count paid by people who left',
      one: '1 paid by someone who left',
    );
    return '$_temp0';
  }

  @override
  String get preSettleReviewReasonExact => 'Exact split';

  @override
  String get preSettleReviewReasonCustom => 'Custom participants';

  @override
  String get preSettleReviewReasonPersonal => 'Personal';

  @override
  String get preSettleReviewReasonLarge => 'Large amount';

  @override
  String get preSettleReviewReasonPayerLeft => 'Payer left';

  @override
  String preSettleReviewMore(int count) {
    return '+$count more';
  }

  @override
  String get preSettleReviewReview => 'Review expenses';

  @override
  String get preSettleReviewContinue => 'Continue to settle';

  @override
  String get settleUpEveryoneEvenHeadline => 'Everyone\'s even.';

  @override
  String settleUpTransfersHeadline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transfers\nuntil everyone\'s even.',
      one: 'One transfer\nuntil everyone\'s even.',
    );
    return '$_temp0';
  }

  @override
  String settleUpNoOptimizedPayments(Object subjectName) {
    return 'No optimized payments are needed across $subjectName.';
  }

  @override
  String settleUpOptimizedPayments(Object subjectName) {
    return 'Optimized to reduce the number of payments across $subjectName.';
  }

  @override
  String settleUpSummaryTransfers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transfers',
      one: '1 transfer',
    );
    return '$_temp0';
  }

  @override
  String settleUpSummaryTotal(Object amount) {
    return '$amount total';
  }

  @override
  String get settleUpEachPersonNet => 'Each person\'s net';

  @override
  String settleUpSettleAllWith(Object name) {
    return 'Settle all with $name';
  }

  @override
  String settleUpSettleAllWithCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count payments',
      one: '1 payment',
    );
    return '$_temp0';
  }

  @override
  String settleUpStepIndicator(int current, int total) {
    return '$current of $total';
  }

  @override
  String settleUpSteppedRecordedAll(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Recorded $count payments.',
      one: 'Recorded 1 payment.',
    );
    return '$_temp0';
  }

  @override
  String settleUpSteppedRecordedAllWillSync(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Recorded $count payments — will sync when online.',
      one: 'Recorded 1 payment — will sync when online.',
    );
    return '$_temp0';
  }

  @override
  String settleUpSteppedRecordedPartial(int recorded, int total) {
    return 'Recorded $recorded of $total payments.';
  }

  @override
  String settleUpSteppedRecordedPartialWillSync(int recorded, int total) {
    return 'Recorded $recorded of $total payments — will sync when online.';
  }

  @override
  String get currencyExplainerTitle => 'Each currency settles separately';

  @override
  String get currencyExplainerBody =>
      'We never invent exchange rates, so OMR can\'t cancel out AED. You\'ll record one payment per currency.';

  @override
  String get currencyExplainerGotIt => 'Got it';

  @override
  String settleScopeNoteEvent(String eventName) {
    return 'This settles balances for $eventName only. Money owed across the rest of the group is settled from the group\'s Settle up.';
  }

  @override
  String get settleScopeNoteGroup =>
      'This is everyone\'s complete balance across the whole group. Recording a payment here won\'t even out each event\'s own ledger — that\'s expected.';

  @override
  String get settleUpPaymentHistory => 'Payment history';

  @override
  String get settleUpUnknown => 'Unknown';

  @override
  String get settleUpPaidConnector => 'paid';

  @override
  String get settleUpShareReceipt => 'Share receipt';

  @override
  String get settleUpViewRecapCta => 'View recap & export';

  @override
  String settleUpReceiptLine(
    Object payerName,
    Object recipientName,
    Object amount,
  ) {
    return '$payerName paid $recipientName $amount';
  }

  @override
  String settleUpReceiptContext(Object date, Object subjectName) {
    return '$date · $subjectName';
  }

  @override
  String get settleUpReceiptFooter => '— recorded in Rihla';

  @override
  String get settleUpReceiptShareSubject => 'Settlement receipt';

  @override
  String get settleUpMarkThisPaidTitle => 'Mark this paid?';

  @override
  String get settleUpMarkThisReceivedTitle => 'Mark this received?';

  @override
  String get settleUpRecordThisTitle => 'Record this payment?';

  @override
  String settleUpMarkThisPaidBody(Object fromName, Object toName) {
    return 'We\'ll close out the balance between $fromName and $toName.';
  }

  @override
  String get settleUpRecordPartialTitle => 'Record a partial payment?';

  @override
  String settleUpRecordPartialBody(Object fromName, Object toName) {
    return 'This is a partial payment — the balance between $fromName and $toName stays open.';
  }

  @override
  String settleUpRemainingAfter(Object fromName, Object toName, Object amount) {
    return '$fromName will still owe $toName $amount after this.';
  }

  @override
  String settleNotifySheetTitle(Object name) {
    return 'Paid — let $name know?';
  }

  @override
  String get settleNotifySheetBody => 'Recorded — send a quick heads-up?';

  @override
  String get settleNotifyMessageLabel => 'Message';

  @override
  String get settleNotifyPickChat =>
      'You choose who to send it to in WhatsApp.';

  @override
  String get settleNotifyNotNow => 'Not now';

  @override
  String get settleNotifyWhatsApp => 'WhatsApp';

  @override
  String settleNotifyMessageEvent(
    Object recipientName,
    Object amount,
    Object eventName,
    Object groupName,
  ) {
    return 'Hey $recipientName, I\'ve sent you $amount for $eventName in $groupName.';
  }

  @override
  String settleNotifyMessageGroup(
    Object recipientName,
    Object amount,
    Object groupName,
  ) {
    return 'Hey $recipientName, I\'ve sent you $amount for $groupName.';
  }

  @override
  String get settleUpNoteHint => 'Add a note (optional)';

  @override
  String settleUpRecordsImmediately(Object name) {
    return 'This records your payment to $name immediately.';
  }

  @override
  String settleUpRecordsReceivedImmediately(Object name) {
    return 'This records $name\'s payment to you immediately.';
  }

  @override
  String settleUpRecordsForOthersImmediately(Object fromName, Object toName) {
    return 'This records $fromName\'s payment to $toName immediately.';
  }

  @override
  String get settleUpDoesntMoveMoney =>
      'Rihla records the payment — it doesn\'t move money.';

  @override
  String get settleUpNotYet => 'Not yet';

  @override
  String get settleUpMarkPaid => 'Mark paid';

  @override
  String get settleUpMarkReceived => 'Mark received';

  @override
  String get settleUpRecordPayment => 'Record';

  @override
  String settleUpPays(Object fromName, Object toName) {
    return '$fromName pays $toName';
  }

  @override
  String get settleUpHideAmountEditor => 'Hide amount editor';

  @override
  String get settleUpTapToEditAmount => 'Tap to edit amount';

  @override
  String settleUpAmountLabel(Object currency) {
    return 'Amount ($currency)';
  }

  @override
  String settleUpSuggestedAmount(Object amount) {
    return 'Suggested: $amount';
  }

  @override
  String get settleUpAllSettledTitle => 'All settled up';

  @override
  String get settleUpAllSettledMessage =>
      'Everyone is square. No outstanding amounts.';

  @override
  String settleUpYouOwe(Object name) {
    return 'You owe $name';
  }

  @override
  String settleUpOwesYou(Object name) {
    return '$name owes you';
  }

  @override
  String settleUpOwes(Object fromName, Object toName) {
    return '$fromName owes $toName';
  }

  @override
  String get commonDone => 'Done';

  @override
  String get commonContinue => 'Continue';

  @override
  String get nameValidationEmpty => 'Name can\'t be empty.';

  @override
  String nameValidationTooLong(int maxLength) {
    return 'Keep it to $maxLength characters or fewer.';
  }

  @override
  String get nameValidationControlChars =>
      'Remove line breaks or special characters.';

  @override
  String get nameValidationReserved => 'That name uses reserved wording.';

  @override
  String get homeActiveJourneys => 'Active journeys';

  @override
  String get homeSeeAll => 'See all';

  @override
  String get homeSeeActivity => 'View activity';

  @override
  String get homeGroups => 'Groups';

  @override
  String get homeNewGroup => 'New group';

  @override
  String get homeRecently => 'Recently';

  @override
  String get homeNoActivityYet => 'No activity yet';

  @override
  String get homeTravellerFallback => 'traveller';

  @override
  String get homeStartFirstGroup => 'Start your first group';

  @override
  String get homeStartFirstGroupBody =>
      'Plan trips, track expenses, and settle up with friends.';

  @override
  String get homeCreateGroup => 'Create Group';

  @override
  String get homeJoinGroup => 'Join Group';

  @override
  String get homeRestoreWithGoogle => 'Sign in with Google to restore';

  @override
  String get homeRestoreWithEmail => 'Restore with email instead';

  @override
  String get homeRestoreSectionCaption => 'Been here before?';

  @override
  String get homeSetNameChip => 'Set your name';

  @override
  String get homeGuestCaption =>
      'Guest account — lives on this phone until you back it up in Profile.';

  @override
  String get restoreGoogleFailed =>
      'Couldn\'t sign in with Google. Please try again.';

  @override
  String get restoreBlockedHasData =>
      'Restoring switches to your saved account and leaves this phone\'s current groups behind — they\'re tied to a temporary identity that can\'t be moved. Resolve them first.';

  @override
  String get homeBackupNudgeTitle => 'Back up your account';

  @override
  String get homeBackupNudgeBody =>
      'Your groups and expenses live only on this phone. Link Google so a new phone, reinstall, or lost device can\'t erase them.';

  @override
  String get homeBackupNudgeCta => 'Link Google account';

  @override
  String get homeBackupNudgeDismiss => 'Not now';

  @override
  String get homeErrorTitle => 'Something went wrong';

  @override
  String get homeErrorMessage =>
      'Check your connection and try again. Your groups are safely synced — we just need internet to fetch the latest.';

  @override
  String get homeCreateAGroup => 'Create a Group';

  @override
  String get homeJoinAGroup => 'Join a Group';

  @override
  String get homeGoodMorning => 'Good morning';

  @override
  String get homeGoodAfternoon => 'Good afternoon';

  @override
  String get homeGoodEvening => 'Good evening';

  @override
  String homeGreeting(Object greeting, Object name) {
    return '$greeting, $name';
  }

  @override
  String get homeNoUpcomingJourneys => 'No upcoming or active journeys';

  @override
  String homeGroupSubtitle(int memberCount, int eventCount) {
    String _temp0 = intl.Intl.pluralLogic(
      memberCount,
      locale: localeName,
      other: '$memberCount members',
      one: '1 member',
    );
    String _temp1 = intl.Intl.pluralLogic(
      eventCount,
      locale: localeName,
      other: '$eventCount events',
      one: '1 event',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get homeTheyOweYou => 'they owe you';

  @override
  String get homeYouOwe => 'you owe';

  @override
  String get homeSettled => 'settled';

  @override
  String get homeAcrossAllJourneys => 'Across all journeys';

  @override
  String get homeBalanceHeroHint => 'See your journeys';

  @override
  String get homeNetYoureOwed => 'Net — you\'re owed';

  @override
  String get homeNetYouOwe => 'Net — you owe';

  @override
  String get homeAllSettledAcrossJourneys => 'All settled across journeys';

  @override
  String get homeOwed => 'owed';

  @override
  String get homeOwe => 'owe';

  @override
  String get homeOwedToYou => 'owed to you';

  @override
  String get homeBalanceUnavailable => 'Balance unavailable';

  @override
  String get homeBalanceIncompleteNotice =>
      'Some data couldn\'t load — balance may be incomplete';

  @override
  String get homeSpendingUnavailable => 'Spending data unavailable';

  @override
  String homeWeeklySpending(Object currency) {
    return 'Weekly Spending ($currency)';
  }

  @override
  String get homeNoSpendingThisWeek => 'No spending this week';

  @override
  String get homeBottomNavGroups => 'Groups';

  @override
  String get homeBottomNavActivity => 'History';

  @override
  String get homeBottomNavProfile => 'Profile';

  @override
  String get historyTabTitle => 'History';

  @override
  String get homeQuickAddExpense => 'Add Expense';

  @override
  String get homeQuickSettleUp => 'Settle Up';

  @override
  String get homeQuickInviteFriend => 'Invite Friend';

  @override
  String get homeQuickActivity => 'Activity';

  @override
  String get addExpenseSheetTitle => 'Add expense to…';

  @override
  String get addExpenseSheetSubtitle =>
      'Your open events, the one you\'re on first.';

  @override
  String addExpenseSheetSubtitleOngoing(Object groupName) {
    return '$groupName · ongoing';
  }

  @override
  String addExpenseSheetSubtitleUpcoming(Object groupName, int days) {
    return '$groupName · in ${days}d';
  }

  @override
  String get addExpenseSheetBrowseAll => 'Browse all groups';

  @override
  String get addExpenseSheetAllGroupsTitle => 'All groups';

  @override
  String get addExpenseSheetAllGroupsSubtitle =>
      'Pick a group, then one of its open events.';

  @override
  String addExpenseSheetOpenEventCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open events',
      one: '1 open event',
      zero: 'No open events',
    );
    return '$_temp0';
  }

  @override
  String get addExpenseSheetNoOpenEventsHint =>
      'No open events — open one in this group first';

  @override
  String get addExpenseSheetPickEventSubtitle => 'Pick an open event.';

  @override
  String get addExpenseSheetEmptyTitle => 'Nothing to add to yet';

  @override
  String get addExpenseSheetEmptyBody =>
      'Expenses live inside a group\'s events. Start a group — it comes with a ready ledger event.';

  @override
  String get addExpenseSheetLoadFailed =>
      'Couldn\'t load your events. Try again.';

  @override
  String get activityTitle => 'Activity';

  @override
  String get activityCaption => 'ACTIVITY';

  @override
  String get activitySubtitle => 'Across every journey, every group';

  @override
  String get activityLoadFailedTitle => 'Could not load activity';

  @override
  String get activityLoadFailedMessage =>
      'Check your connection and try again.';

  @override
  String get activityReload => 'Reload';

  @override
  String get activityPartialFailure => 'Some activity couldn\'t load';

  @override
  String get activityNoActivityTitle => 'No activity yet';

  @override
  String get activityCrossGroupEmptyMessage =>
      'Activity from all your groups will appear here.';

  @override
  String get activityEventEmptyMessage =>
      'Actions by you and your group members will appear here.';

  @override
  String get activityGroupEmptyMessage =>
      'Group events, payments, and member changes will appear here.';

  @override
  String get activityNoFilterTitle => 'Nothing matches this filter';

  @override
  String get activityNoFilterMessage =>
      'Try a different filter, or switch back to All.';

  @override
  String get activityFilterAll => 'All';

  @override
  String get activityFilterSettles => 'Settlements';

  @override
  String get activityFilterSettlements => 'Settlements';

  @override
  String get activityFilterEvents => 'Events';

  @override
  String get activityFilterMembers => 'Members';

  @override
  String get activityFilterExpenses => 'Expenses';

  @override
  String get activitySearchTooltip => 'Search';

  @override
  String get activitySearchClose => 'Close search';

  @override
  String get activitySearchHint => 'Search activity';

  @override
  String get activitySearchNoMatchesTitle => 'No matches';

  @override
  String activitySearchNoMatchesMessage(Object query) {
    return 'Nothing in your loaded activity matches \"$query\".';
  }

  @override
  String get activitySearchOlder => 'Search older activity';

  @override
  String activitySearchLoadedCount(int count) {
    return 'Searching $count loaded entries';
  }

  @override
  String get activityEventMissingTitle => 'This event no longer exists';

  @override
  String get activityEventMissingMessage => 'It may have been deleted.';

  @override
  String get activityRelativeJustNow => 'JUST NOW';

  @override
  String activityRelativeMinutes(int count) {
    return '${count}M';
  }

  @override
  String activityRelativeHours(int count) {
    return '${count}H';
  }

  @override
  String activityRelativeDays(int count) {
    return '${count}D';
  }

  @override
  String get activitySomeone => 'Someone';

  @override
  String get activityAuditPayerLabel => 'Payer';

  @override
  String get activityEventMoneyCreated => 'added an expense';

  @override
  String get activityEventMoneyUpdated => 'updated an expense';

  @override
  String get activityEventMoneyDeleted => 'deleted an expense';

  @override
  String get activityEventGearCreated => 'added a gear entry';

  @override
  String get activityEventGearUpdated => 'updated a gear entry';

  @override
  String get activityEventGearDeleted => 'deleted a gear entry';

  @override
  String get activityEventDocsCreated => 'added a document';

  @override
  String get activityEventDocsUpdated => 'updated a document';

  @override
  String get activityEventDocsDeleted => 'deleted a document';

  @override
  String get activityGroupSettlementDescription => 'recorded a settlement';

  @override
  String activitySettlementPaid(Object toName) {
    return 'paid $toName';
  }

  @override
  String activitySettlementReceived(Object fromName) {
    return 'received a payment from $fromName';
  }

  @override
  String activitySettlementBetween(Object fromName, Object toName) {
    return 'recorded a settlement from $fromName to $toName';
  }

  @override
  String get activityGroupEventCreatedGeneric => 'created an event';

  @override
  String activityGroupEventCreated(Object eventName) {
    return 'created $eventName';
  }

  @override
  String get activityGroupEventDeletedGeneric => 'deleted an event';

  @override
  String activityGroupEventDeleted(Object eventName) {
    return 'deleted $eventName';
  }

  @override
  String get activityGroupMemberJoined => 'joined the group';

  @override
  String get activityGroupMemberLeft => 'left the group';

  @override
  String activityGroupMemberRemoved(Object memberName) {
    return 'removed $memberName from the group';
  }

  @override
  String activityGroupExpenseAdded(Object eventName) {
    return 'added an expense in $eventName';
  }

  @override
  String get activityGroupExpenseAddedGeneric => 'added an expense';

  @override
  String activityGroupExpenseEdited(Object eventName) {
    return 'edited an expense in $eventName';
  }

  @override
  String get activityGroupExpenseEditedGeneric => 'edited an expense';

  @override
  String activityGroupExpenseDeleted(Object eventName) {
    return 'deleted an expense in $eventName';
  }

  @override
  String get activityGroupExpenseDeletedGeneric => 'deleted an expense';

  @override
  String get activityTitlePaymentRecorded => 'Payment recorded';

  @override
  String get activityTitleEventCreated => 'Event created';

  @override
  String get activityTitleEventRemoved => 'Event removed';

  @override
  String get activityTitleMemberJoined => 'Member joined';

  @override
  String get activityTitleMemberLeft => 'Member left';

  @override
  String get activityTitleGeneric => 'Activity';

  @override
  String get eventTypeTripLabel => 'Trip';

  @override
  String get eventTypeTripShort => 'TRIP';

  @override
  String get eventTypeTripDescription =>
      'Plan a shared trip with expenses and activity';

  @override
  String get eventTypeCampingLabel => 'Camping';

  @override
  String get eventTypeCampingShort => 'CAMPING';

  @override
  String get eventTypeCampingDescription =>
      'Outdoor trip with shared expense tracking';

  @override
  String get eventTypeTravelLabel => 'Travel';

  @override
  String get eventTypeTravelShort => 'TRAVEL';

  @override
  String get eventTypeTravelDescription =>
      'Journey with group expenses and activity';

  @override
  String get eventTypeNightDayOutLabel => 'Night/Day Out';

  @override
  String get eventTypeNightDayOutShort => 'NIGHT/DAY OUT';

  @override
  String get eventTypeNightDayOutDescription =>
      'Quick outing with expense splitting';

  @override
  String get eventTypeCustomLabel => 'Custom';

  @override
  String get eventTypeCustomShort => 'EVENT';

  @override
  String get eventTypeCustomDescription => 'Start from a flexible event setup';

  @override
  String get eventNew => 'New event';

  @override
  String get eventSecondEventHint =>
      'Events split one group\'s spending into separate trips or outings — most groups only need one.';

  @override
  String get eventNameLabel => 'Event Name';

  @override
  String get eventNameHint => 'e.g. Summer camping trip';

  @override
  String get eventDatesLabel => 'Dates';

  @override
  String get eventOptionalLabel => '(optional)';

  @override
  String get eventStartDate => 'Start date';

  @override
  String get eventEndDate => 'End date';

  @override
  String get eventCreate => 'Create Event';

  @override
  String get eventCreating => 'Creating…';

  @override
  String get eventSelectAtLeastOneParticipant =>
      'Select at least one participant.';

  @override
  String get eventCreateFailed =>
      'Couldn\'t create event. Check your connection and try again.';

  @override
  String get eventCreatedWillSync => 'Event saved — will sync when online.';

  @override
  String get eventParticipants => 'Participants';

  @override
  String get eventSelectAll => 'Select All';

  @override
  String get eventSettingsTitle => 'Event Settings';

  @override
  String get eventSettingsLoadFailed => 'Could not load settings';

  @override
  String get eventNotFound => 'Event not found';

  @override
  String get eventDetailsSection => 'EVENT DETAILS';

  @override
  String get eventNameEmpty => 'Event name can\'t be empty.';

  @override
  String get eventUpdated => 'Event updated';

  @override
  String get eventUpdatedWillSync => 'Event updated — will sync when online.';

  @override
  String get eventSaveFailed => 'Couldn\'t save changes. Try again.';

  @override
  String get eventNotSet => 'Not set';

  @override
  String get eventDescriptionLabel => 'Description';

  @override
  String get eventSaveChanges => 'Save Changes';

  @override
  String get eventDangerZone => 'DANGER ZONE';

  @override
  String get eventUnsettledWarning => 'This event has unsettled balances.';

  @override
  String get eventDelete => 'Delete event';

  @override
  String get eventDeleteQuestion => 'Delete this event?';

  @override
  String get eventDeleteBody =>
      'This will permanently delete the event and all its expenses, settlements, and activity. This cannot be undone.';

  @override
  String get eventDeleteBodyWithUnsettled =>
      'This will permanently delete the event and all its expenses, settlements, and activity. This cannot be undone.\n\nThis event has unsettled balances. Settle up before deleting, or proceed anyway.';

  @override
  String get eventKeepEvent => 'Keep event';

  @override
  String eventDeleteFailed(Object error) {
    return 'Failed to delete event: $error';
  }

  @override
  String get eventClose => 'Close event';

  @override
  String get eventReopen => 'Reopen event';

  @override
  String get eventCloseQuestion => 'Close this event?';

  @override
  String get eventCloseBody =>
      'Spending will be frozen — no new or edited expenses. You can still settle up, and you can reopen the event later.';

  @override
  String get eventCloseConfirm => 'Close event';

  @override
  String get eventReopenQuestion => 'Reopen this event?';

  @override
  String get eventReopenBody => 'Expenses can be added and edited again.';

  @override
  String get eventReopenConfirm => 'Reopen';

  @override
  String eventCloseFailed(Object error) {
    return 'Failed to close event: $error';
  }

  @override
  String eventReopenFailed(Object error) {
    return 'Failed to reopen event: $error';
  }

  @override
  String eventClosedBannerBy(Object name) {
    return 'Closed by $name · spending frozen';
  }

  @override
  String get eventClosedBanner => 'Closed · spending frozen';

  @override
  String get eventViewReceipt => 'View recap';

  @override
  String get editorEventClosedTitle => 'Event closed';

  @override
  String get editorEventClosedMessage =>
      'This event is closed and its spending is frozen. Reopen it from Settings to add or edit expenses.';

  @override
  String get eventTabExpenses => 'Expenses';

  @override
  String get eventTabSettleUp => 'Settle up';

  @override
  String get eventTabActivity => 'Activity';

  @override
  String get eventTabRecap => 'Recap';

  @override
  String get eventAddExpense => 'Add expense';

  @override
  String get eventYourBalance => 'Your balance';

  @override
  String get eventYouAreOwed => 'You are owed';

  @override
  String get eventYouOwe => 'You owe';

  @override
  String get eventAllSettled => 'All settled';

  @override
  String get eventNothingToSettleYet => 'Nothing to settle yet';

  @override
  String get eventEveryoneSquare => 'Everyone is square on this trip.';

  @override
  String get eventAddFirstExpenseHint =>
      'Add the first expense to start splitting.';

  @override
  String get eventBreakdownOwesYou => 'owes you';

  @override
  String get eventBreakdownYouOwe => 'you owe';

  @override
  String get eventTripTotal => 'Trip total';

  @override
  String get eventTotalLabelCamping => 'Camping total';

  @override
  String get eventTotalLabelOuting => 'Outing total';

  @override
  String get eventTotalLabelEvent => 'Event total';

  @override
  String eventExpenseCountInline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count expenses',
      one: '1 expense',
    );
    return '· $_temp0';
  }

  @override
  String get eventLedgerLink => 'Ledger →';

  @override
  String get eventRecent => 'Recent';

  @override
  String get eventSeeAll => 'See all →';

  @override
  String get eventYouPaid => 'You paid';

  @override
  String eventPaidByName(Object name) {
    return '$name paid';
  }

  @override
  String get eventAddFirstExpenseTitle => 'Add the first expense';

  @override
  String get eventAddFirstExpenseBody => 'Pick who paid, split it fairly.';

  @override
  String eventPeopleOverline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
    );
    return '$_temp0';
  }

  @override
  String eventSplittingBetweenYouAndOthers(int othersCount) {
    String _temp0 = intl.Intl.pluralLogic(
      othersCount,
      locale: localeName,
      other: 'Splitting between you and $othersCount others',
      one: 'Splitting between you and 1 other',
    );
    return '$_temp0';
  }

  @override
  String get eventYou => 'You';

  @override
  String eventDayOf(int currentDay, int totalDays) {
    return 'Day $currentDay of $totalDays';
  }

  @override
  String get eventLoadFailedTitle => 'Could not load event';

  @override
  String get eventMissingMessage =>
      'It may have been deleted, or the link is incorrect.';

  @override
  String eventSemanticCard(Object eventName, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
    );
    return '$eventName, $_temp0';
  }

  @override
  String eventYouOweAmount(Object amount, Object currency) {
    return 'You owe $currency $amount';
  }

  @override
  String eventYouAreOwedAmount(Object amount, Object currency) {
    return 'You are owed $currency $amount';
  }

  @override
  String get groupNameLabel => 'Group Name';

  @override
  String get groupNameHint => 'e.g. Family trip';

  @override
  String get groupYourNameInGroupLabel => 'Your name';

  @override
  String get groupYourNameHint => 'how friends will see you';

  @override
  String get groupDifferentNameHelper =>
      'Shown in all your groups. Changing it anywhere updates it everywhere.';

  @override
  String groupCreateError(Object error) {
    return 'Error: $error';
  }

  @override
  String get groupCreatedWillSync => 'Group created — will sync when online.';

  @override
  String get groupNew => 'New group';

  @override
  String get groupEditTitle => 'Edit group';

  @override
  String get groupCreate => 'Create';

  @override
  String get groupMoodTitle => 'Who\'s coming along?';

  @override
  String get groupMoodBody =>
      'A group is a circle of people you share expenses with — a household, a travel crew, a project team.';

  @override
  String get groupGlyph => 'Stamp';

  @override
  String get groupStampInk => 'Ink';

  @override
  String get groupStampSymbol => 'Symbol';

  @override
  String get groupStampMonogramHint => 'Your initial is the default';

  @override
  String get groupDefaultCurrency => 'Default currency';

  @override
  String get groupCreatorTitle => 'You\'re the creator.';

  @override
  String get groupCreatorBody =>
      'Once created, share an invite code to bring others in.';

  @override
  String get groupInviteCodeCopied => 'Invite code copied';

  @override
  String groupShareMessage(Object code) {
    return 'Join my group on Rihla! Use code $code to join.';
  }

  @override
  String groupShareSubject(Object name) {
    return 'Join $name';
  }

  @override
  String get groupShareCodeWithGroup => 'Share this code with your group';

  @override
  String get groupCopyCode => 'Copy Code';

  @override
  String get groupShare => 'Share';

  @override
  String get groupShareViaWhatsApp => 'WhatsApp';

  @override
  String get groupJoinTitle => 'Join a Group';

  @override
  String get groupJoinCta => 'Join Group';

  @override
  String get groupJoining => 'Joining…';

  @override
  String get groupYourName => 'Your name';

  @override
  String get groupJoinNameHint => 'how the group will see you';

  @override
  String get groupInviteCode => 'Invite code';

  @override
  String get groupInviteCodeHelper =>
      'Ask a group member for their 6-character code';

  @override
  String get groupJoinHintTitle => 'You\'ll see balances right away.';

  @override
  String get groupJoinHintBody =>
      'Joining is instant — no approval needed once the code matches.';

  @override
  String get groupJoinMoodTitle => 'Got an invite?';

  @override
  String get groupJoinMoodBody =>
      'Enter the 6-character code a friend gave you. We will drop you straight into the group.';

  @override
  String get groupJoinInvalidCode =>
      'That code doesn\'t match any group. Check the code and try again.';

  @override
  String get groupJoinAlreadyMember => 'You\'re already in this group.';

  @override
  String get groupJoinNameTaken =>
      'That name\'s already used in this group. Please pick a different name.';

  @override
  String displayNameTakenInGroup(Object groupName) {
    return 'That name\'s already used in $groupName. Please pick a different name.';
  }

  @override
  String get groupJoinTooManyAttempts => 'Too many attempts. Try again later.';

  @override
  String get groupJoinPleaseSignIn => 'Please sign in and try again.';

  @override
  String get groupJoinDeviceVerificationFailed =>
      'Could not verify this device. Try again, or update from the Play Store.';

  @override
  String get groupJoinFailed =>
      'Couldn\'t join the group. Check your connection and try again.';

  @override
  String get groupMemberJoinedDescription => 'joined the group';

  @override
  String get groupMemberLeftDescription => 'left the group';

  @override
  String get groupEvents => 'Events';

  @override
  String get groupMembers => 'Members';

  @override
  String get groupPeople => 'People';

  @override
  String get groupInsightsTitle => 'Insights';

  @override
  String get insightsTotalSpent => 'Total spent';

  @override
  String get insightsTopEvent => 'Biggest event';

  @override
  String get insightsTopPayer => 'Fronted the most';

  @override
  String get insightsTopConsumer => 'Biggest share';

  @override
  String get groupNoEventsTitle => 'No events yet';

  @override
  String get groupNoEventsMessage =>
      'Create your first event to start planning together.';

  @override
  String get groupCreateEvent => 'Create Event';

  @override
  String get groupInvitePeople => 'Invite people';

  @override
  String get groupLoadEventsFailed => 'Couldn\'t load events';

  @override
  String groupMemberCountCaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count MEMBERS',
      one: '1 MEMBER',
    );
    return 'GROUP · $_temp0';
  }

  @override
  String get groupMoreTooltip => 'Group options';

  @override
  String get groupSettings => 'Group settings';

  @override
  String get groupActivity => 'Activity';

  @override
  String get groupYourBalanceHere => 'Your balance here';

  @override
  String get groupTheyOweYou => 'they owe you';

  @override
  String get groupYouOwe => 'you owe';

  @override
  String get groupAllSettled => 'all settled';

  @override
  String get groupSettleUp => 'Settle up';

  @override
  String groupEventEnds(Object date) {
    return 'ends $date';
  }

  @override
  String get groupYourShare => 'your share';

  @override
  String get groupNoShare => 'no share';

  @override
  String get groupMembersLoadFailed => 'Couldn\'t load members';

  @override
  String get groupMembersLoading => 'Loading members…';

  @override
  String get groupFormerMember => 'Former member';

  @override
  String get groupRoleYou => 'You';

  @override
  String get groupRoleCreator => 'Creator';

  @override
  String get groupBalanceShownAbove => 'shown above';

  @override
  String get groupLoadFailedTitle => 'Could not load group';

  @override
  String get groupNoAccessTitle => 'You no longer have access';

  @override
  String get groupNoAccessMessage =>
      'You\'re no longer a member of this group, or it\'s no longer shared with you.';

  @override
  String get groupNotFoundTitle => 'Group not found';

  @override
  String get groupNotFoundMessage =>
      'It may have been deleted, or the link is incorrect.';

  @override
  String get groupBackHome => 'Back home';

  @override
  String get groupSettingsTitle => 'Group settings';

  @override
  String get groupDefaults => 'Defaults';

  @override
  String get groupCurrency => 'Currency';

  @override
  String get groupCurrencyLockedNote =>
      'Currency is set when the group is created and can\'t be changed.';

  @override
  String get groupMembersCreatorOnlyNote =>
      'Only the group creator can add or remove members.';

  @override
  String get groupSettingsLoadFailed => 'Could not load settings';

  @override
  String get groupTryAgain => 'Try again';

  @override
  String get groupInvite => 'Invite';

  @override
  String groupCreatedDateCurrency(Object date, Object currency) {
    return 'Created $date · $currency';
  }

  @override
  String get groupAnyoneWithCodeCanJoin => 'Anyone with the code can join';

  @override
  String get groupEditNameSemantic => 'Edit group name';

  @override
  String get groupCopyInviteCodeSemantic => 'Copy invite code';

  @override
  String get groupShowQrCodeSemantic => 'Show QR code';

  @override
  String get groupShowQrCode => 'Show QR code';

  @override
  String get groupShareInviteSemantic => 'Share invite';

  @override
  String groupUpdateNameFailed(Object error) {
    return 'Failed to update name: $error';
  }

  @override
  String get groupDangerZone => 'Danger zone';

  @override
  String get groupDangerZoneCreatorOnly => 'Danger zone · Creator only';

  @override
  String get groupLeaveThisGroup => 'Leave this group';

  @override
  String get groupLeaveSubtitle =>
      'You\'ll lose access to its events and expenses.';

  @override
  String get groupLeave => 'Leave';

  @override
  String get groupDeleteThisGroup => 'Delete this group';

  @override
  String get groupDeleteSubtitle => 'All events and expenses will be lost.';

  @override
  String get groupDelete => 'Delete';

  @override
  String get groupLeaveQuestion => 'Leave group?';

  @override
  String get groupLeaveBody =>
      'You\'ll lose access to all events and data in this group.';

  @override
  String get groupStayInGroup => 'Stay in group';

  @override
  String get groupLeaveGroup => 'Leave group';

  @override
  String get groupSettleBeforeLeaving => 'Settle up before leaving the group.';

  @override
  String groupFailedLeave(Object error) {
    return 'Failed to leave group: $error';
  }

  @override
  String get groupSettleBeforeDeleting =>
      'All members must settle up before deleting the group.';

  @override
  String groupFailedDelete(Object error) {
    return 'Failed to delete group: $error';
  }

  @override
  String get groupDeleteSheetTitle => 'Delete this group?';

  @override
  String get groupDeleteSheetRemovesPrefix => 'Removes ';

  @override
  String groupDeleteSheetMembersBody(int count) {
    return ' for all $count members. Events, expenses, and balances inside it are erased. ';
  }

  @override
  String get groupDeleteSheetEveryoneBody =>
      ' for everyone. Events, expenses, and balances inside it are erased. ';

  @override
  String get groupDeleteSheetUndo => 'This can\'t be undone.';

  @override
  String get groupDeleteSheetTypePrefix => 'TYPE ';

  @override
  String get groupDeleteSheetTypeSuffix => ' TO CONFIRM';

  @override
  String get groupDeleteSheetRetention =>
      'A copy is kept for 30 days in case you change your mind.';

  @override
  String get groupDeleteSheetConfirm => 'Delete group';

  @override
  String get groupScanToJoin => 'Scan to join';

  @override
  String get groupInviteQrCode => 'Invite QR code';

  @override
  String get groupOrEnterCode => 'OR ENTER CODE';

  @override
  String get groupCopyLink => 'Copy link';

  @override
  String get groupLinkCopied => 'Link copied';

  @override
  String groupShareInviteMessage(Object groupName, Object uri, Object code) {
    return 'Join \'$groupName\' on Rihla: $uri or use code $code.';
  }

  @override
  String groupShareInviteSubject(Object groupName) {
    return 'Join \'$groupName\' on Rihla';
  }

  @override
  String get groupAddMemberAction => 'Add member';

  @override
  String get groupShadowNotJoinedBadge => 'Not joined yet';

  @override
  String get groupAddPersonTitle => 'Add a person';

  @override
  String get groupAddPersonSubtitle =>
      'Add someone by name now; they can join later with the invite code.';

  @override
  String get groupAddPersonAction => 'Add';

  @override
  String groupRemoveMemberTooltip(Object name) {
    return 'Remove $name from group';
  }

  @override
  String get groupRoleMember => 'Member';

  @override
  String groupSettleWithBeforeRemoving(Object name) {
    return 'Settle up with $name before removing them.';
  }

  @override
  String groupFailedRemoveMember(Object name, Object error) {
    return 'Failed to remove $name: $error';
  }

  @override
  String get onboardingBrandKicker => 'RIHLA · ر.ح.ل.ة';

  @override
  String get onboardingBrandHeadlineLead => 'Trips,\ntallied with\n';

  @override
  String get onboardingBrandHeadlineAccent => 'care';

  @override
  String get onboardingBrandHeadlineSuffix => '.';

  @override
  String get onboardingBrandBody =>
      'A travel ledger for friends, families and crews who want the trip to be the memory — not the math.';

  @override
  String get onboardingBegin => 'Begin';

  @override
  String get onboardingHowTitle => 'Three ways\nit travels with you.';

  @override
  String get onboardingHowGroupsTitle =>
      'Groups for the people you travel with';

  @override
  String get onboardingHowGroupsBody =>
      'A travel crew, a roommates group, a family. People stay; events come and go.';

  @override
  String get onboardingHowEventsTitle => 'Events for the trips & nights out';

  @override
  String get onboardingHowEventsBody =>
      'Trips, dinners, weekends. Each gets a cover, a dates window, and its own ledger.';

  @override
  String get onboardingHowExpensesTitle => 'Expenses split in three taps';

  @override
  String get onboardingHowExpensesBody =>
      'Equally, by share, or however. Math happens in the background — settle when you like.';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingSetupTitle => 'A few things\nbefore we begin.';

  @override
  String get onboardingNameSection => 'What should we call you?';

  @override
  String get onboardingCurrencySection => 'Home currency';

  @override
  String get onboardingCurrencyHelper => 'Each group can override this later.';

  @override
  String get onboardingNotificationsSection => 'Notifications';

  @override
  String get onboardingOpenRihla => 'Open Rihla';

  @override
  String get onboardingNameHint => 'Your name';

  @override
  String onboardingCurrencySemantics(Object currency) {
    return '$currency currency';
  }

  @override
  String get onboardingActivitySettlesTitle => 'Activity & settles';

  @override
  String get onboardingActivitySettlesSubtitle => 'When friends add or pay';

  @override
  String get onboardingWeeklyDigestTitle => 'Weekly digest';

  @override
  String get onboardingWeeklyDigestSubtitle => 'A Sunday summary';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String onboardingStepSemantics(int active, int count) {
    return 'Onboarding step $active of $count';
  }

  @override
  String get expenseSuccessTitle => 'Expense Saved';

  @override
  String get expenseSuccessSyncedToCloud => 'SYNCED TO CLOUD';

  @override
  String get expenseSuccessWillSync => 'SAVED — WILL SYNC';

  @override
  String get expenseSuccessDone => 'Done';

  @override
  String get expenseSuccessAddAnother => 'Add Another';

  @override
  String get expenseSuccessTotalAmount => 'TOTAL AMOUNT';

  @override
  String get expenseSuccessCategory => 'CATEGORY';

  @override
  String get commonNotFound => 'Not Found';

  @override
  String get commonEmail => 'Email';

  @override
  String get commonEmailHintExample => 'you@example.com';

  @override
  String get authWelcomeBack => 'Welcome back';

  @override
  String get authRecoverTitle => 'Restore from email';

  @override
  String get authRecoverDescription =>
      'Enter the email you linked on your old device. We\'ll send a one-tap sign-in link.';

  @override
  String get authRecoverSubmit => 'Send recovery link';

  @override
  String get authErrorSendLink =>
      'Couldn\'t send the link. Check your connection and try again.';

  @override
  String get authErrorAccountNotFound =>
      'We couldn\'t find a Rihla account with this email. Make sure you linked it on your previous device first.';

  @override
  String get authErrorRateLimited =>
      'Too many attempts. Wait a few minutes and try again.';

  @override
  String get authErrorOffline =>
      'No connection. Check your internet and try again.';

  @override
  String authErrorGeneric(Object code) {
    return 'Something went wrong ($code). Please try again.';
  }

  @override
  String get errorNetwork => 'Please check your connection and try again.';

  @override
  String get errorPermissionDenied => 'You don\'t have permission to do that.';

  @override
  String get errorTooManyRequests =>
      'Too many attempts. Please wait a moment and try again.';

  @override
  String get errorUnexpected => 'Something went wrong. Please try again.';

  @override
  String get authErrorEmailAlreadyLinked =>
      'This email is already linked to a Rihla account. Restore from that account instead.';

  @override
  String get authErrorInvalidEmail => 'That doesn\'t look like a valid email.';

  @override
  String get authErrorEmailsDontMatch => 'Emails don\'t match.';

  @override
  String get authLinkEmailTitle => 'Link your email';

  @override
  String get authLinkEmailHeading => 'So you can come back';

  @override
  String get authLinkEmailDescription =>
      'We\'ll email you a one-tap sign-in link. If you ever lose your phone or clear app data, enter the same email on a new device to get all your trips back.';

  @override
  String get authLinkEmailConfirmLabel => 'Confirm email';

  @override
  String get authLinkEmailSubmit => 'Send link';

  @override
  String get authLinkEmailPrivacyNote =>
      'Your email is used only to restore your Rihla data. We don\'t send marketing email and we don\'t share it.';

  @override
  String get authRecoverPendingTitle => 'Check your inbox';

  @override
  String get authRecoverPendingDescriptionPrefix =>
      'We sent a sign-in link to ';

  @override
  String get authRecoverPendingDescriptionSuffix =>
      '. Tap it on this device — we\'ll pull your trips back automatically.';

  @override
  String get authLinkEmailSentDescriptionSuffix =>
      '. Tap it on this device to finish linking.';

  @override
  String get authRecoverPendingSpamHint =>
      'Can\'t find it? Check your spam folder. The link is good for 24 hours.';

  @override
  String get authRecoverPendingLinkSeen =>
      'We saw your link. Hang tight — restoring now.';

  @override
  String get authRecoverPendingResendStatus => 'New link sent.';

  @override
  String authRecoverPendingResendErrorCode(Object code) {
    return 'Couldn\'t resend ($code).';
  }

  @override
  String get authRecoverPendingResendErrorGeneric =>
      'Couldn\'t resend. Try again in a bit.';

  @override
  String get authRecoverPendingResendLink => 'Resend link';

  @override
  String authRecoverPendingResendCountdown(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get groupSettleUpMissingTitle => 'This group is no longer available';

  @override
  String get groupSettleUpMissingMessage =>
      'You may have been removed. Tap below to go back home.';

  @override
  String groupSettleUpEventLabelFallback(Object suffix) {
    return 'Event ...$suffix';
  }

  @override
  String get groupSettleUpAcrossEventsLabel => 'Across events';

  @override
  String errorPageNotFound(Object location) {
    return 'Page not found: $location';
  }

  @override
  String get errorPageNotFoundTitle => 'Page not found';

  @override
  String get errorPageNotFoundBody =>
      'It may have been deleted, or the link is incorrect.';

  @override
  String get splashTagline => 'your shared journey';

  @override
  String get splashErrorTitle => 'Something\'s off';

  @override
  String get splashErrorBody => 'We couldn\'t start the app.';

  @override
  String get splashRetry => 'Try again';

  @override
  String get notificationRationaleTitle => 'Stay in the loop';

  @override
  String get notificationRationaleBody =>
      'Get notified when someone adds an expense or settles up.';

  @override
  String get notificationRationaleNotNow => 'Not now';

  @override
  String get notificationRationaleTurnOn => 'Turn on';

  @override
  String get durableGateTitle => 'Keep your money safe';

  @override
  String get durableGateBody =>
      'Your groups and expenses are tied to this account. Link Google so they can\'t be lost with this device.';

  @override
  String get durableGateContinueGoogle => 'Continue with Google';

  @override
  String get durableGateNotNow => 'Not now';

  @override
  String get durableGateConflict =>
      'That Google account already belongs to another Rihla account. Switching to it would leave this phone\'s current groups behind — they\'re tied to a temporary identity that can\'t be moved. Resolve them first, then use a different Google account.';

  @override
  String get durableGateConflictTitle => 'That account already has Rihla data';

  @override
  String get durableGateConflictSwitchBody =>
      'This Google account already has Rihla data. Switch to it? This device will continue with that account.';

  @override
  String get durableGateSwitch => 'Switch account';

  @override
  String get durableGateUseDifferent => 'Use a different account';

  @override
  String get durableGateError => 'Could not link your account. Try again.';

  @override
  String get createGroupWhoElse => 'Who\'s in?';

  @override
  String get createGroupAddNameHint => 'Type a name…';

  @override
  String get createGroupShadowOfflineHint => 'Connect to add names';

  @override
  String get shadowAddRequiresLink =>
      'Link your account to add people by name — anyone can still join with the invite code.';

  @override
  String createGroupShadowNameTaken(Object name) {
    return '\"$name\" is already used in this group.';
  }

  @override
  String get createGroupShadowAddFailed =>
      'Some names could not be added. You can add them from the group later.';

  @override
  String get groupClaimPickerTitle => 'Is one of these you?';

  @override
  String get groupClaimPickerSubtitle =>
      'Someone added these names before you joined. Claim your spot to inherit your share.';

  @override
  String get groupClaimImNew => 'No, I\'m new';

  @override
  String groupClaimConfirmTitle(Object name) {
    return 'Claim $name\'s spot?';
  }

  @override
  String groupClaimConfirmWarning(Object name) {
    return 'This permanently merges $name\'s expenses into your account. It can\'t be undone, and the group creator must approve.';
  }

  @override
  String groupClaimConfirmCta(Object name) {
    return 'Yes, claim $name\'s spot';
  }

  @override
  String get groupClaimWaitingTitle => 'Waiting for approval';

  @override
  String groupClaimWaitingBody(Object name) {
    return 'We sent your request to the group creator. You\'ll join $name\'s spot once they approve.';
  }

  @override
  String get groupClaimCheckAgain => 'Check again';

  @override
  String get groupClaimStillPending =>
      'Still waiting for the creator to approve.';

  @override
  String get groupClaimDeclinedBody =>
      'The creator declined your claim. You can join as a new member instead.';

  @override
  String get groupClaimNameTakenClaimInstead =>
      'That name belongs to someone added earlier. Claim it above, or pick a different name.';

  @override
  String get groupClaimRequestsTitle => 'Claim requests';

  @override
  String groupClaimRequestRow(Object requester, Object shadow) {
    return '$requester wants to claim $shadow\'s spot';
  }

  @override
  String groupClaimMergeConsequence(Object shadow, Object requester) {
    return 'Approving merges $shadow\'s expenses into $requester. This can\'t be undone.';
  }

  @override
  String get groupClaimPendingBadge => 'Pending';

  @override
  String get groupClaimApprove => 'Approve';

  @override
  String get groupClaimDecline => 'Decline';

  @override
  String groupClaimApproved(Object requester, Object shadow) {
    return '$requester now holds $shadow\'s spot.';
  }

  @override
  String get groupClaimRequestDeclined => 'Request declined.';

  @override
  String get groupClaimApproveError =>
      'Couldn\'t complete the claim. Try again.';

  @override
  String get groupClaimNoRequests => 'No pending claim requests.';

  @override
  String get recapButtonTooltip => 'Recap';

  @override
  String recapPeopleExpenses(int people, int expenses) {
    String _temp0 = intl.Intl.pluralLogic(
      people,
      locale: localeName,
      other: '$people people',
      one: '1 person',
    );
    String _temp1 = intl.Intl.pluralLogic(
      expenses,
      locale: localeName,
      other: '$expenses expenses',
      one: '1 expense',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get recapTotalSpent => 'Total spent';

  @override
  String recapSpendingFrozen(String date) {
    return 'Spending frozen · closed $date';
  }

  @override
  String get recapSpendingFrozenNoDate => 'Spending frozen';

  @override
  String get recapYouTitle => 'You';

  @override
  String get recapYouPaid => 'You paid';

  @override
  String get recapYourShare => 'Your share';

  @override
  String get recapSettlements => 'Settlements';

  @override
  String get recapNet => 'Net';

  @override
  String get recapEmptyTitle => 'Nothing to wrap up yet';

  @override
  String get recapEmptyMessage => 'Add an expense to see this event\'s recap.';

  @override
  String get recapTopPayer => 'Top payer';

  @override
  String get recapBiggestExpense => 'Biggest expense';

  @override
  String get recapByCategory => 'By category';

  @override
  String get recapWhoPaid => 'Who paid';

  @override
  String get recapWhoUpDown => 'Who\'s up / down';

  @override
  String get recapSettledRow => 'settled';

  @override
  String get recapYouSuffix => 'you';

  @override
  String get recapSettledTitle => 'Everyone\'s settled up';

  @override
  String get recapSettledSubtitle => 'No outstanding balances in this event.';

  @override
  String get recapOutstandingTitle => 'Outstanding balances';

  @override
  String recapOutstandingSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people still owe',
      one: '1 person still owes',
    );
    return '$_temp0.';
  }

  @override
  String get recapSettleCtaTitle => 'Ready to settle up?';

  @override
  String get recapSettleCtaBody =>
      'Settle just this event, or net your balances across the whole group.';

  @override
  String get recapSettleThisEvent => 'Settle this event';

  @override
  String get recapSettleAtGroup => 'Settle at group level';

  @override
  String get recapMultiCurrencyNote =>
      'Balances are kept per currency — they\'re never added together.';

  @override
  String get recapShareButton => 'Share recap';

  @override
  String get recapShareCta => 'Share image';

  @override
  String get recapExportCsvButton => 'Export ledger (CSV)';

  @override
  String get recapExportPdfButton => 'Export ledger (PDF)';

  @override
  String get recapShareError => 'Couldn\'t create the image. Please try again.';

  @override
  String recapShareText(String eventName) {
    return '$eventName — our trip recap, tracked with Rihla';
  }

  @override
  String recapCardCaption(String month) {
    return 'Rihla · Wrapped · $month';
  }

  @override
  String get recapCardCaptionPlain => 'Rihla · Wrapped';

  @override
  String get recapCardPeople => 'People';

  @override
  String get recapCardExpenses => 'Expenses';

  @override
  String get recapCardAvgPerDay => 'Avg / day';

  @override
  String get recapCardPerPerson => 'Per person';

  @override
  String get recapCardTopSpender => 'Top spender';

  @override
  String get recapCardBiggest => 'Biggest splurge';

  @override
  String get recapCardWhereItWent => 'Where it went';

  @override
  String get recapCardAllSettled => 'All settled';

  @override
  String recapCardStillToSettle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count still to settle',
      one: '1 still to settle',
    );
    return '$_temp0';
  }
}
