# Rihla Closed-Test Access Kit

Date: 2026-06-27

Purpose: remove Google Play closed-testing friction from the first-100 launch.

## Why This Exists

Rihla is currently on a Google Play alpha/closed-testing track. That is fine for
a controlled first cohort, but it breaks casual sharing unless every tester can
actually open the Play listing and install.

For the first 100 users, treat Play access as its own funnel step:

1. Champion agrees.
2. Champion sends the Google account they use in Play.
3. Email is added to the Play tester list.
4. Champion opens the Play tester opt-in link.
5. Champion installs from Google Play.
6. Champion creates a Rihla group and invites real users.

Do not count a champion as ready until step 4 is confirmed.

Public explainer pages:

- English: `https://rihla-safar.web.app/alpha`
- Arabic: `https://rihla-safar.web.app/ar/alpha`

Use these when a tester needs the access steps, but keep the official Play
opt-in link private to the tester group.

## Source-Backed Constraints

Google Play Console supports internal, closed, and open testing tracks. Closed
testing is useful for targeted cohorts, but testers need a valid tester setup
before they can install unreleased builds.

Operational rules to respect:

- Use the Play Console testing flow and shareable testing links for testers.
- Closed-test tester access can be managed through email lists or Google Groups.
- If using email CSV upload, upload the full intended list, not only the newest
  people, because CSV upload replaces previously entered email addresses in that
  tester list.
- New personal Play developer accounts may need a qualifying closed-test period
  before production access is available; do not assume the closed alpha can be
  replaced by production distribution immediately.

Sources:

- Google Play closed testing overview:
  https://play.google.com/console/about/closed-testing/
- Google Play app testing help:
  https://support.google.com/googleplay/android-developer/answer/9845334
- Google Play personal account testing requirement:
  https://support.google.com/googleplay/android-developer/answer/14151465

## Play Console Checklist

Use this before every outreach batch.

1. Open Play Console.
2. Go to Rihla, then Testing, then Closed testing.
3. Open the active `first`/alpha track.
4. Confirm release `1.6.3+27` is available to testers.
5. Open the Testers tab.
6. Add the tester email list or Google Group used for first-100 outreach.
7. Copy the official opt-in/testing link shown by Play Console.
8. Save that link outside git as `RIHLA_PLAY_OPT_IN_LINK`.
9. Send the opt-in link before the public landing link when the person is not
   already a tester.
10. Send `/alpha` or `/ar/alpha` if they need the install steps explained.
11. Ask the champion to confirm they saw the Play install button.

## Private Email Handling

Do not commit real tester emails to this repo.

Keep the working email list in a private local file, for example:

```text
~/Desktop/rihla-first-100-play-testers.csv
```

Recommended columns for the private working file:

```csv
slot,champion,google_play_email,segment,added_to_play,opted_in,installed,notes
```

If champion names are filled but Google Play emails are still blank, generate a
private access-request packet before building the Play upload:

```bash
dart tool/first_100_access_requests.dart \
  "$HOME/Desktop/rihla-first-10-roster.csv" \
  --output=/tmp/rihla-first-10-access-requests.md
```

Send `/tmp/rihla-first-10-access-requests.md` privately, then fill
`google_play_email` in the private roster as replies arrive. The command prints
only slot numbers and counts to the terminal.

Before uploading to Play Console, export only the email column into the format
Play expects. Keep all already-active testers in the exported list so an upload
does not accidentally remove access for people who were already added.

After each Play Console update, keep a private one-email-per-line copy of the
currently active tester list outside git, for example:

```text
~/Desktop/rihla-active-play-testers.csv
```

Generate the upload file from the private roster and merge in the active tester
list. Omit `--include-existing=...` only for the first upload when no active
tester file exists yet.

```bash
dart tool/export_play_tester_emails.dart \
  ~/Desktop/rihla-first-100-play-testers.csv \
  --include-existing="$HOME/Desktop/rihla-active-play-testers.csv" \
  --output=/tmp/rihla-play-testers.csv
```

The export writes one email per line, removes duplicates, skips blank email
rows, rejects invalid email-looking values, and writes UTF-8 without a BOM.
Upload the generated `/tmp/rihla-play-testers.csv` file to Play Console, then
replace the private active tester file with the same generated file.

## Access-First Messages

Use this before asking someone to test the app.

English:

```text
Quick access step first: which Google account do you use in the Play Store?

Rihla is still on Android alpha, so I need to add that Google account before the install link works.
```

Arabic:

```text
أولًا أحتاج خطوة الوصول: ما حساب Google الذي تستخدمه في Google Play؟

Rihla لا يزال في Android alpha، لذلك أحتاج أضيف هذا الحساب قبل أن يعمل رابط التثبيت.
```

After adding them:

```text
I added your Google Play account for Rihla alpha access.

1. Open this tester link first: PLAY_OPT_IN_LINK
2. Confirm you joined the test.
3. Install Rihla from Google Play.
4. Create one group and add one real shared expense.

If Play says the app is unavailable, check that you are signed into the same Google account you sent me.

Access help page: https://rihla-safar.web.app/alpha
```

Arabic:

```text
أضفت حساب Google Play الخاص بك للوصول إلى Rihla alpha.

1. افتح رابط المختبرين أولًا: PLAY_OPT_IN_LINK
2. أكد الانضمام للتجربة.
3. ثبت Rihla من Google Play.
4. أنشئ مجموعة واحدة وأضف مصروفًا حقيقيًا مشتركًا.

إذا ظهر في Play أن التطبيق غير متاح، تأكد أنك تستخدم نفس حساب Google الذي أرسلته لي.

صفحة المساعدة للوصول: https://rihla-safar.web.app/ar/alpha
```

## Tracker Rules

Use `first-100-cohort-tracker.csv` for public-safe status only:

- `tester_added`: `yes` only when the Play tester list includes that person.
- `top_blocker`: use exact values like `needs Google Play email`,
  `opt-in link not opened`, `wrong Google account`, `Play unavailable`, or
  `installed but no group created`.
- Never paste real emails into the tracker unless the file is kept private and
  out of git.

## Escalation Rules

If fewer than 7 of the first 10 champions can install within 24 hours:

1. Stop broad outreach.
2. Fix the Play access instructions.
3. Send a short screen recording showing the opt-in step.
4. Consider moving to open testing when QA/release readiness allows it.

If 7+ can install but fewer than 4 create groups:

1. Keep acquisition running.
2. Improve the first-create-group script.
3. Prioritize product activation blockers over more SEO work.
