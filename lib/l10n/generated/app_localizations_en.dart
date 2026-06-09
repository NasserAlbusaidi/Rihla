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
  String get deleteAccountRetryTitle => 'Deletion didn\'t finish';

  @override
  String get deleteAccountRetryContent =>
      'Some of your account data was removed, but the deletion didn\'t finish. Your account is still signed in. Retrying will complete it.';

  @override
  String get signOutTitle => 'Sign out of this device?';

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
  String get categoryFood => 'Food & Dining';

  @override
  String get categoryTransport => 'Transport';

  @override
  String get categoryAccommodation => 'Accommodation';

  @override
  String get categoryActivities => 'Activities';

  @override
  String get categoryShopping => 'Shopping';

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
  String get ledgerEndOfLedger => 'END OF LEDGER';

  @override
  String get ledgerEmptyStateTitle => 'An empty page, ready to be written.';

  @override
  String ledgerEmptyStateFirstExpenseBody(Object currency) {
    return 'The first $currency you log will set the trip total. We\'ll split it equally between everyone on the trip.';
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
  String get editorEvent => 'Event';

  @override
  String get editorDate => 'Date';

  @override
  String get editorDeleteThisExpense => 'Delete this expense';

  @override
  String get editorDeleteThisExpenseBody =>
      'Removes for everyone in this event.';

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
  String get editorShadowProfile => 'Shadow Profile';

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
  String get editorScopeGlobal => 'Equally';

  @override
  String get editorScopeSubGroup => 'Group split';

  @override
  String get editorScopeCustom => 'Custom';

  @override
  String get editorScopePersonal => 'Personal';

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
  String settleUpAmountExceedsOutstanding(Object amount) {
    return 'Amount cannot exceed the outstanding balance of $amount';
  }

  @override
  String get settleUpRecorded => 'Settlement recorded.';

  @override
  String get settleUpRecordFailed =>
      'Couldn\'t record settlement. Check your connection and try again.';

  @override
  String get settleUpEveryoneEvenHeadline => 'Everyone\'s even.';

  @override
  String settleUpTransfersHeadline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transfers,\neveryone\'s even.',
      one: 'One transfer,\neveryone\'s even.',
    );
    return '$_temp0';
  }

  @override
  String settleUpNoOptimizedPayments(Object subjectName) {
    return 'No optimized payments are needed across $subjectName.';
  }

  @override
  String settleUpOptimizedPayments(Object subjectName) {
    return 'Optimized to minimise the number of payments across $subjectName.';
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
  String get settleUpPaymentHistory => 'Payment history';

  @override
  String get settleUpUnknown => 'Unknown';

  @override
  String get settleUpPaidConnector => 'paid';

  @override
  String get settleUpMarkThisPaidTitle => 'Mark this paid?';

  @override
  String get settleUpMarkThisReceivedTitle => 'Mark this received?';

  @override
  String settleUpMarkThisPaidBody(Object fromName, Object toName) {
    return 'We\'ll close out the balance between $fromName and $toName.';
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
  String get settleUpNotYet => 'Not yet';

  @override
  String get settleUpMarkPaid => 'Mark paid';

  @override
  String get settleUpMarkReceived => 'Mark received';

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
  String get settleUpMethodCash => 'Cash';

  @override
  String get settleUpMethodBank => 'Bank';

  @override
  String get settleUpMethodOther => 'Other';

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
  String get homeRecover => 'I had Rihla before — restore';

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
  String get homeBottomNavActivity => 'Activity';

  @override
  String get homeBottomNavProfile => 'Profile';

  @override
  String get homeQuickAddExpense => 'Add Expense';

  @override
  String get homeQuickSettleUp => 'Settle Up';

  @override
  String get homeQuickInviteFriend => 'Invite Friend';

  @override
  String get homeQuickActivity => 'Activity';

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
  String get activityFilterActivity => 'Activity';

  @override
  String get activityFilterSettles => 'Settles';

  @override
  String get activityFilterSettlements => 'Settlements';

  @override
  String get activityFilterEvents => 'Events';

  @override
  String get activityFilterMembers => 'Members';

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
  String get activityEventMoneyCreated => 'added a money entry';

  @override
  String get activityEventMoneyUpdated => 'updated a money entry';

  @override
  String get activityEventMoneyDeleted => 'deleted a money entry';

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
  String get eventPickerTitle => 'What kind of\njourney is this?';

  @override
  String get eventPickerSubtitle =>
      'We\'ll set sensible defaults for categories and splits.';

  @override
  String eventContinueWith(Object type) {
    return 'Continue with $type';
  }

  @override
  String get eventNew => 'New event';

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
  String get groupYourNameInGroupLabel => 'Your name in this group';

  @override
  String get groupYourNameHint => 'how friends will see you';

  @override
  String get groupDifferentNameHelper =>
      'You can use a different name in each group.';

  @override
  String groupCreateError(Object error) {
    return 'Error: $error';
  }

  @override
  String get groupNew => 'New group';

  @override
  String get groupCreate => 'Create';

  @override
  String get groupMoodTitle => 'Who\'s coming along?';

  @override
  String get groupMoodBody =>
      'A group is a circle of people you share expenses with — a household, a travel crew, a project team.';

  @override
  String get groupGlyph => 'Group glyph';

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
  String get groupNoEventsTitle => 'No events yet';

  @override
  String get groupNoEventsMessage =>
      'Create your first event to start planning together.';

  @override
  String get groupCreateEvent => 'Create Event';

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
  String get groupMoreTooltip => 'More';

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
  String get groupLoadFailedTitle => 'Could not load group';

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
  String get groupDefaultSplit => 'Default split';

  @override
  String get groupDefaultSplitEqual => 'Equal';

  @override
  String get groupReminders => 'Reminders';

  @override
  String get groupRemindersWeekly => 'Weekly';

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
  String get groupShareInviteSemantic => 'Share invite';

  @override
  String get groupNameEmpty => 'Group name can\'t be empty.';

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
  String get groupManage => 'Manage';

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
  String get authSignOutFirstTitle => 'This device is already in use';

  @override
  String get authSignOutFirstBody =>
      'To restore a different account, you\'ll lose the trips and expenses on this device. They\'ll stay in the cloud only if they\'re tied to a different linked email — otherwise they\'ll be orphaned.';

  @override
  String get authSignOutFirstConfirm => 'Sign out and continue';

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
  String errorPageNotFound(Object location) {
    return 'Page not found: $location';
  }

  @override
  String get splashTagline => 'your shared journey';

  @override
  String get splashErrorTitle => 'Something\'s off';

  @override
  String get splashErrorBody => 'We couldn\'t start the app.';

  @override
  String get splashRetry => 'Try again';
}
