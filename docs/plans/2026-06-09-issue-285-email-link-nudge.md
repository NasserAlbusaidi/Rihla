# #285 — Surface the anonymous data-loss risk + proactively prompt email-link

**Issue:** #285 (P2, privacy/design). Identity is a device-bound anonymous UID; reinstall / new phone / clear-data orphans **all** group + expense data unless an email was linked beforehand. The only surfacing today is the buried Profile "Linked email: Not set" row, and the empty-state "restore" link vanishes once a group exists. **Fix:** a one-time, non-blocking nudge to link an email after the first group, with copy that states the actual stakes.

**Gate:** NOT required. Client-only UI. No `BalanceCalculator`/money math, no `firestore.rules`/Functions, no routing-tree change (reuses the existing `/profile/link-email` route), no Firestore schema/field change. The only new persisted state is a local SharedPreferences boolean.

## Done looks like

On the home dashboard, an anonymous user who has ≥1 group sees a dismissible "back up your account" card directly under the balance hero. Tapping **Add email** routes to the existing `LinkEmailScreen`. Tapping **Not now** (or the close affordance) hides it permanently. Once an email is linked the card never shows again, regardless of the dismiss flag. A user with no groups (empty state) is unaffected — they already have the `/recover` CTA.

## Visibility predicate

The card renders **iff**:
1. `linkedEmailProvider == null` (purely anonymous — has data to lose), **AND**
2. `settings.emailLinkNudgeSeen == false` (not yet dismissed).

The "has ≥1 group" condition is **structurally guaranteed**: the card lives only inside `_buildLoaded`, which `_DashboardContentState.build` renders only when `groups.isNotEmpty` (`home_screen.dart:96-97`). So the card cannot appear before the user has a group — this is the issue's "after the first group" trigger and directly fixes "the restore link vanishes once a group exists."

Linking an email flips `linkedEmailProvider` non-null (Firebase `User.email`), so condition 1 fails and the card disappears even if the dismiss flag was never set — no stale nag after the user solves the problem.

## Callsite classification (new write path)

- `emailLinkNudgeSeen` — **OUTBOUND** to SharedPreferences only (mirrors `notificationPromptSeen` exactly). No Firestore boundary, no money, no read-path coupling beyond the widget's own `settingsProvider.select`. Persisted via the existing `SettingsService` round-trip.

## Steps (each leaves the tree green)

1. **RED** — `test/features/home/account_backup_nudge_test.dart`:
   - shows for anon user (`linkedEmailProvider` → null) with the dismiss flag false;
   - hidden when an email is linked (`linkedEmailProvider` → `'a@b.com'`);
   - hidden when `emailLinkNudgeSeen == true`;
   - **Add email** pushes `/profile/link-email`;
   - **Not now** / close calls `setEmailLinkNudgeSeen(true)` and the card disappears.
2. `AppSettings.emailLinkNudgeSeen` (model) — bool field, default false, in ctor + `copyWith`. Mirror `notificationPromptSeen`.
3. `SettingsService` — `_emailLinkNudgeSeenKey = 'settings_email_link_nudge_seen'`; load in `loadSettings`; `saveEmailLinkNudgeSeen`.
4. `SettingsNotifier.setEmailLinkNudgeSeen(bool)`.
5. `AccountBackupNudge` widget — `lib/features/home/widgets/account_backup_nudge.dart`, `ConsumerWidget`; returns `SizedBox.shrink()` when predicate false; design-token card; `HomeKeys.accountBackupNudge` + CTA/dismiss keys.
6. Inject as a `SliverToBoxAdapter` after the `BalanceHeroCard` sliver in `_buildLoaded`.
7. l10n (`app_en.arb` + `app_ar.arb`): `homeBackupNudgeTitle`, `homeBackupNudgeBody`, `homeBackupNudgeCta`, `homeBackupNudgeDismiss`.
8. `flutter gen-l10n` (or build), `flutter analyze` clean, run home tests + the new test + settings tests.

## Copy (honest stakes — no soft-pedalling)

- **Title:** "Back up your account"
- **Body:** "Your groups and expenses live only on this phone. Add an email so a new phone, reinstall, or lost device can't erase them."
- **CTA:** "Add email" · **Dismiss:** "Not now"

## Out of scope (one PR does one thing)

- Strengthening the Profile "Not set" row copy — the home nudge is the surfacing; touch Profile copy separately if wanted.
- Any change to the email-link flow itself (`LinkEmailScreen`), recovery, or auth.
- Re-showing logic / reminder cadence — the issue specifies *one-time*.
