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
  String get deleteAccountTitle => 'Delete your account?';

  @override
  String get deleteAccountContent =>
      'This permanently deletes your Rihla account. Your linked email (if any) will be released so it can be reused. Trips, expenses, and balances tied to your account become unreachable. There\'s no undo.';

  @override
  String get deleteAccountConfirm => 'Delete account';

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
  String get ledgerEmptyStateFirstExpenseBody =>
      'The first OMR you log will set the trip total. We\'ll split it equally between everyone on the trip.';

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
  String get editorCategory => 'Category';

  @override
  String get editorPaidBy => 'Paid by';

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
  String settleUpMarkThisPaidBody(Object fromName, Object toName) {
    return 'We\'ll close out the balance between $fromName and $toName.';
  }

  @override
  String get settleUpNoteHint => 'Add a note (optional)';

  @override
  String settleUpNotifyToConfirm(Object name) {
    return '$name will be notified to confirm.';
  }

  @override
  String get settleUpNotYet => 'Not yet';

  @override
  String get settleUpMarkPaid => 'Mark paid';

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
}
