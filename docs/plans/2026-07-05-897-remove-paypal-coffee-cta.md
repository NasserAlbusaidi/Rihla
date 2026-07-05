# #897 Remove Unsupported Coffee CTA

## Problem

The Profile "Buy me a coffee" tile launches PayPal's donate endpoint, but the
destination rejects the configured organization/country. The external launch
itself succeeds, so the app cannot detect the broken destination.

## Decision

For the 1.7.4 public-release fix, remove the payment/support CTA entirely
instead of replacing it with another provider. Keep Help, Feedback, Terms,
Privacy, account recovery, and account deletion unchanged.

## Scope

- Remove the Profile support tile and PayPal donate URL.
- Remove dead keys and l10n strings that exist only for that tile.
- Add a regression test proving the public Profile screen does not expose the
  retired coffee CTA.

## Out Of Scope

- Adding a new donation/payment provider.
- Changing legal/help/feedback links.
- Changing account, profile identity, notifications, theme, language, default
  split, or app version UI.

## Acceptance

- Profile does not render `profile_coffee_tile`.
- Profile does not render `Buy me a coffee`.
- Runtime `lib/` code has no PayPal donate URL or launcher path.
- Profile and settings widget tests still pass.
- Analyzer stays clean.
