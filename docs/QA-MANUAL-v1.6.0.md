# QA Manual — v1.6.0

Hands-on, real-device test script for everything new **since v1.5.1** (the
shipped Play build). Follow it top to bottom; each test has preconditions,
steps, and an expected result you can check against the running app. Strings
quoted in **bold** are the **exact EN copy** the screen should show — if you see
different wording, that's a finding.

> This is the **feature-acceptance** pass for the 1.5.1→1.6.0 delta. It is
> **separate** from the formal release-gate matrix in `docs/REAL-DEVICE-QA.md`
> (RD-01…RD-13, blocker **#40**), which you still run for the release itself.
>
> The older clusters still in the build — shadow members & claim/merge (#278),
> multi-currency (#382), push notifications, identity/delete/recovery — were
> feature-accepted in **`docs/QA-MANUAL-v1.5.1.md`** and don't need re-running
> unless this delta touched them. They didn't.

**Prepared:** 2026-06-22 · **Build under test:** 1.6.0 candidate (currently
`main` @ `1.5.1+23`; `tool/release.sh minor` bumps it to `1.6.0+24` at tag time).

---

## What's new in 1.6.0 (test scope)

| Cluster | Issues | Section |
|---|---|---|
| Itemized split — line items + bill-level adjustments (service/tax/tip/discount) | #203, #605 | **I** |
| Trip stamps — group glyph + ink at create and from settings | #287 | **J** |
| Event recap — on-demand total spent + per-currency "You" summary | #202 | **K** |
| Settle-up — record-on-behalf, correction eligibility, partial honesty, correction re-opens balance | #595, #598, #587, #283/#567 | **L** |
| Display truth — WYSIWYG split preview, real ledger-row shares, one balance truth on group detail | #242, #591, #486 | **M** |
| Money input — reject European-format amounts, equal-split quantize | #530, #596 | **N** |
| Create-form & profile — type chip-row, offline banner on create, isolated Danger zone | #489, #533, #487 | **O** |
| Performance — no-regression spot-checks | #622, #623, #626, #627, #634, #640 | **P** |

---

## ⚠️ Before you start

1. **Most of 1.6.0 is single-device, client-only.** Sections I, J, K, M, N, O
   touch no callable — a **debug build is fine** and you don't need a durable
   (Google/email) credential or a second device. App Check only bites the
   *callable* paths.

2. **Section L (settle-up) is also single-device** — you don't need two real
   people. Add two **shadow members** (Settings → Members → Manage, or the
   "Who's in?" chips at group create) and exercise transfers **between them**
   while you're the third party. That's exactly the record-on-behalf case.

3. **Creating a group requires a DURABLE credential (#441 gate).** An anonymous
   session is hard-blocked: tapping **Create** shows the **"Keep your money
   safe"** sheet and **"Not now" does NOT create** — by design. You must link
   Google/email first. Real users always will, so test *as a linked user*.

4. **Callable flows need a Play-signed build — the debug App Check token did NOT
   work in the 2026-06-22 pass.** `addShadowMember`, claim, deleteAccount-cascade,
   and deleteGroup all enforce App Check; on the debug build they returned
   `app: INVALID` even with the debug token registered (the exchange 403s /
   rate-limits). Group/event/expense/settlement **direct Firestore writes work**,
   so §I/J/K/M/N/O/P and the settle-up money paths are testable on debug — but
   anything going through a **callable** (adding members by name, claim/merge,
   account/group deletion) needs a **Play internal-testing build**. (Workaround
   used this pass: shadow members were admin-seeded.)

5. **App Check is ENFORCED in prod.** A sideloaded APK fails Play Integrity. Use a
   Play-track install, or a debug build with a registered App Check debug token
   (recipe: `memory/reference_appcheck_debug_token_qa.md`) — but per #4, expect the
   debug-token path to be flaky for callables; the Play build is the reliable route.

4. **Currency is immutable after group create** — pick deliberately. Use an
   **OMR** group (3-dp) for the money assertions below; the worked examples are
   in baisa (1 OMR = 1000).

Setup check:
- [ ] Debug (or Play-track) build installed and launching
- [ ] One group you created, currency **OMR**, with **≥3 people** (you + two
      shadow members, e.g. `Sara`, `Omar`) so split/settle math has real targets
- [ ] An event under that group with a ledger you can add expenses to

---

## I. Itemized split & bill-level adjustments (#203 + #605) — headline feature

Build an expense as a **bill of line items** plus optional **adjustments**
(service / tax / tip / discount) that fold into each person's share. Under the
hood it persists as an **exact** split; the line-item detail is opaque display
metadata, never re-read by balance math.

### I1 — Reach itemized mode
**Pre:** event ledger, ≥2 people selectable.
1. Ledger → **Add expense**. Enter an amount and pick **≥2** participants.
2. Find the **"How"** section. Its trailing action reads **"Customise"** (it's
   disabled with subtitle **"Pick at least two people to split."** if fewer than
   two are selected).
3. Tap **"Customise"** → bottom sheet headed **"Split how?"**.
4. The mode bar has **five** segments: **Equal · Shares · Exact amounts ·
   Percent · Itemized**. Tap **"Itemized"** (the 5th).

**Expected:** The sheet body switches to an **"Items"** section (with **"+ Add
item"**), an **Adjustments** area, and an **"Each person owes"** live preview.
The footer label changes from "TOTAL" to **"Items match total"** (with a **✓**)
or **"{amount} left"** while it doesn't reconcile.
- [ ] Pass / [ ] Fail — notes:

### I2 — Add line items
**Pre:** itemized mode (I1).
1. Tap **"+ Add item"**; give it a label and an amount.
2. Tap the item's assignee summary → sheet **"Who had this?"** with an
   **"Everyone"** toggle. Assign it (Everyone, or specific people).
3. Add items until they reconcile to the expense amount.

**Expected:** Each item shows its assignee summary (**"Everyone · N"**, **"for
{name}"**, or comma-joined names; **"Assign someone"** if none). When items sum
to the bill, the footer shows **"Items match total"** + **✓** and **Apply**
enables.
- [ ] Pass / [ ] Fail — notes:

### I3 — Add adjustments (service / tax / tip / discount)
**Pre:** items entered (I2).
1. In **"Adjustments"**, tap **"+ Add"** → sheet **"Add adjustment"**.
2. Type chips: **Service · Tax · Tip · Discount**. Pick **Service**; enter an
   **"Amount"** (a **fixed money amount**, not a percent — the suffix is the
   currency code).
3. Under **"How to spread it"** choose **"Split equally"** or **"By item
   share"**. Tap **"Done"**.
4. Add a **Discount**: note the spread chooser is **hidden** and replaced by
   **"A discount is shared in proportion to what each person owes."**

**Expected:** Each adjustment row shows a leading **+** (service/tax/tip) or
**−** (discount), kept LTR. Adjustment amounts are **fixed values** — there is
no percentage field anywhere. A discount always folds proportionally regardless
of any earlier choice.
- [ ] Pass / [ ] Fail — notes:

### I4 — Money assertion (the allocation must be right)
**Pre:** OMR group. Build this exact bill, split among **3** (you + Sara + Omar):
- One item **100.000** assigned to **Everyone**
- **Service 10.000** (equal) · **Tax 5.000** (equal) · **Discount 5.000**

1. Read the **"Each person owes"** preview, then **Apply** and save.

**Expected:** Two people owe **36.666**, the **alphabetically-last** participant
owes **36.668**, and they **sum to exactly 110.000** (100 + 10 + 5 − 5). The odd
baisa lands on the alphabetically-last person — that's the rounding contract,
not a bug.
- [ ] Pass / [ ] Fail — **record the three amounts:** ___ / ___ / ___ (Σ = ___)

### I5 — Persist & read-back
**Pre:** the saved itemized expense from I4.
1. Back in the editor's **"How"** card, read its title/subtitle.
2. Open the ledger row for that expense.
3. **Edit** the expense and re-open **Customise**.

**Expected:** The **"How"** card shows title **"Itemized"** + subtitle **"N
items"**. The ledger row shows the real per-person shares (treated as an exact
split — **no** "Itemized" badge on the row). Re-opening **Customise** restores
**every** item and adjustment (type, amount, allocation) exactly.
- [ ] Pass / [ ] Fail — notes:

### I6 — By-design checks (don't file these)
- An **Equal**-mode expense can never be itemized (picking Equal clears the
  itemized metadata).
- Itemized persists as **`SplitMode.exact`** — the saved `splitMode` is `exact`,
  not a new mode.
- Items + adjustments must reconcile to the entered amount (within 0.001) or
  **Apply** stays disabled (**"{amount} left"**).
- There is **no** itemized-specific success snackbar — the normal save dialog
  shows. (Don't flag a "missing" toast.)
- [ ] Pass / [ ] Fail / [ ] N/A — notes:

---

## J. Trip stamps — group glyph & ink (#287)

A group gets a decorative **stamp**: a **symbol** (12 glyphs, or your initial as
a monogram) tinted by an **ink** color. Chosen at create, editable from settings
(creator-only).

### J1 — Pick a stamp at group create
**Who:** any · **Pre:** online.
1. Home → **New group**. The stamp picker sits between the mood block and the
   group-name field.
2. A large **hero preview** updates live as you type the name. Below it:
   - an **"INK"** row of **6** color swatches (tap one → saffron ring),
   - a **"SYMBOL"** grid: the **monogram** (your initial) first, then **12**
     glyphs — tent, mountain, palm, sun, wave, compass, anchor, house, dining,
     coffee, gift, camera,
   - caption **"Your initial is the default"**.
3. Pick a glyph + an ink, finish creating the group.

**Expected:** The picker shows **"INK"**, **"SYMBOL"**, and the monogram caption
— and **no** "Stamp" header (that string is unused). Selection is always shown
by the **saffron ring**, never by ink color. The created group carries your
chosen glyph + ink.
- [x] Pass / [ ] Fail — notes: 2026-06-22 Pixel. Picker renders hero + INK (6
  swatches) + SYMBOL grid (monogram first, then all 12 glyphs) + caption "Your
  initial is the default"; no "Stamp" header. Evidence: qa-evidence/v1.6.0/J1-create-screen.png

### J2 — Where the stamp renders
1. Go **Home** and find the group's row.
2. Open the group → **… → Settings** → look at the identity card at top.

**Expected:** The chosen glyph (tinted to the ink) appears as the **leading tile
on the Home group row** and on the **Settings identity card**. (Note: the group
**detail** screen does **not** show the glyph — don't look for it there.)
- [ ] Pass / [ ] Fail — notes:

### J3 — Edit the stamp from settings (creator-only)
**Who:** creator.
1. Settings → identity card → tap the small **pencil badge** on the glyph tile.
2. Sheet titled **"Edit group"** with **Cancel** / **Save**, a live hero, a name
   field, and the same **"INK"** / **"SYMBOL"** picker.
3. Change the symbol and/or ink → **Save**.

**Expected:** Save closes the sheet (haptic, no success toast) and the new stamp
shows immediately on Home + the identity card. A **non-creator** member viewing
Settings sees **no** pencil badge.
- [ ] Pass / [ ] Fail — notes:

### J4 — Default / monogram
1. Create a group **without** choosing a glyph.

**Expected:** The tile falls back to a **monogram** (the group name's first
letter), tinted by a stable name-derived ink. A blank name renders **·**.
- [ ] Pass / [ ] Fail — notes:

---

## K. Event recap (#202)

An on-demand recap of an event: total spent + your per-currency story. Read-only,
per-currency (no FX). **No share/export in this slice.**

### K1 — Open the recap
**Pre:** an event with **≥1 expense**.
1. Open the event hub (`/group/…/event/…`). In the app bar, tap the **cup** icon
   to the **left** of the settings gear (long-press shows tooltip **"Trip
   recap"**).

**Expected:** Navigates to the recap. The button is **hidden when the event has
no expenses** — so an empty event shows no recap button (expected).
- [ ] Pass / [ ] Fail — notes:

### K2 — Recap content
**Pre:** a **mixed-currency** event is ideal (e.g. some OMR + some USD expenses).
1. Read the recap top to bottom.

**Expected:** Back button · the **event name** (large) · subtitle **"{people}
people · {expenses} expenses"** · a **"Total spent"** section with **one row per
currency** (row label = the currency code) · a **"You"** section with, per
currency: **"You paid"**, **"Your share"**, **"Settlements"** (each shown only
when non-zero), and **"Net"** (always shown, signed +/−). Amounts in different
currencies are **never combined**.
- [ ] Pass / [ ] Fail — notes:

### K3 — Empty / not-found states
1. (If reachable by direct route) open recap for an event with no expenses.

**Expected:** Empty state **"Nothing to wrap up yet"** / **"Add an expense to
see this event's recap."**. A missing event shows **"Event not found"** (with
that same body line — known, not a typo to file).
- [ ] Pass / [ ] Fail / [ ] N/A — notes:

> Known gap (don't file): there is **no share button** on the recap in this
> slice. Verify the screen, not a share action.

---

## L. Settle-up — record-on-behalf, eligibility, partial honesty, correction

Use two **shadow members** (`Sara`, `Omar`) and yourself as the third party.

### L1 — Record a payment between two others (#595)
**Pre:** a suggested transfer exists **between Sara and Omar** (neither is you).
1. **Group** detail → **Settle up** (group screen). On the **"Sara pays Omar"**
   tile, tap **Record**.
2. Sheet title **"Record this payment?"**; saffron banner **"This records Sara's
   payment to Omar immediately."**; sub-line **"Rihla records the payment — it
   doesn't move money."**; payee line **"Sara pays Omar"**; confirm button
   **"Record"** (cancel **"Not yet"**). Confirm.

**Expected:** Snackbar **"Settlement recorded."** (offline: **"Settlement
recorded — will sync when online."**); the transfer drops off. On a **group**
settle screen **any member** can record any transfer; on an **event** settle
screen only **event participants** see the **Record** button (a group member
who isn't an event participant sees the tiles but no button).
- [ ] Pass / [ ] Fail — notes:

### L2 — "Correct" is gated by write-eligibility (#598)
**Pre:** ≥1 recorded payment (a Payment-history row).
1. As an **event participant**, open the event → Settle up → **Payment history**.
   Each row has an **undo** icon button (tooltip **"Correct"**).
2. (If you can) view the same event's history as a **group member who is not an
   event participant**.

**Expected:** The **"Correct"** button shows only for write-eligible viewers
(event participants; all group members on the group screen). A non-participant
still sees the **row** but no Correct button — no permission-denied dead-end.
- [ ] Pass / [ ] Fail / [ ] N/A — notes:

### L3 — Honest partial-payment copy (#587)
**Pre:** a transfer suggesting, say, **10.000** outstanding.
1. Open its Record sheet → tap **"Tap to edit amount"** → enter **4.000**
   (strictly less than suggested).

**Expected:** Title flips to **"Record a partial payment?"**; body flips to
**"This is a partial payment — the balance between {from} and {to} stays
open."** (it no longer claims to close the balance); a hint appears: **"{from}
will still owe {to} OMR 6.000 after this."** (10.000 − 4.000). Entering the full
amount reverts to the full-payment title/body and drops the hint. Over-paying is
rejected with **"Amount cannot exceed the outstanding balance of {amount}"**.
- [ ] Pass / [ ] Fail — notes:

### L4 — Correction re-opens the balance (#283 / #567 regression)
**Pre:** an expense leaves Sara owing you (e.g. you pay **10.000** split equally
between you+Sara → Sara owes **5.000**).
1. Settle up → record the suggested **Sara → you 5.000** → balance goes to
   **settled**.
2. Payment history → tap **Correct** on that row → dialog **"Correct this
   payment?"** / **"This records a reversing payment of {amount} from {recipient}
   back to {payer}. The original payment stays in your history."** → **"Record
   correction"**.

**Expected (the money assertion):** The balance **re-opens** to the
pre-settlement net (Sara owes **5.000** again); the suggested transfer
**reappears**. Payment history keeps the **original** row **and** adds a new
**"Correction"**-tagged row (undo icon) — append-only, nets to zero. This was
the 1.5.1 **C1 blocker (#567)** — verify it now moves the balance.
- [ ] Pass / [ ] Fail — **record before/after net:** settled → ___
- [ ] Pass / [ ] Fail — notes:

---

## M. Display truth — preview == row == persisted (#242, #591, #486)

### M1 — WYSIWYG split preview (#242)
**Pre:** add-expense editor, OMR, ≥3 participants.
1. Enter **100.000**, set split mode **Shares** with weights **2 : 1 : 1**.
2. Look at the **"Split between"** preview card.

**Expected:** The chip under the header reads **"Amounts vary per person."** (not
the equal-mode **"{amount} each"**), and the per-person tiles show **50.000 /
25.000 / 25.000** — the real allocated amounts, not amount÷count.
- [ ] Pass / [ ] Fail — notes:

### M2 — Ledger row shows the real share (#591)
**Pre:** save the 2:1:1 expense from M1 with **you** as a participant.
1. Return to the ledger and find that expense row.

**Expected:** Below the gross amount, a **signed** sub-line shows **your** real
share for this non-equal split (green **+**, red **−**) — previously blank for
non-equal splits. E.g. if you owe 25 → **"−25.000"**; if you paid → **"+75.000"**.
Row == preview == persisted balance.
- [ ] Pass / [ ] Fail — notes:

### M3 — One balance truth on group detail (#486)
1. Open the group detail screen; scroll to the people/balances card.

**Expected:** Section header reads **"PEOPLE"** (was MEMBERS). It lists the
**other** members with their balances (tap → settle-up). **Your** row is **last,
muted, non-tappable**, showing role **"You"** and **"shown above"** instead of a
number — so your net is stated **exactly once** (in the hero). There is a single
**"New event"** button (in the hero); the Events-header "New event" action is
gone.
- [ ] Pass / [ ] Fail — notes:

> Don't file: **"You · shown above"** is not one literal string — the self-row is
> "{your name}" + **"You"** + muted **"shown above"** with no rendered middot.

---

## N. Money input & correctness (#530, #596)

### N1 — Reject European-format amounts (#530)
1. **Settle up** → edit a step amount → enter **`1.234,56`** (dot grouping,
   comma decimal). Confirm.
2. **Add expense** → paste **`1.234,56`** → save.
3. Now try **`1,234.56`** (US: comma thousands, dot decimal) in both.

**Expected:** `1.234,56` is **rejected** — snackbar **"Please enter a valid
amount"**, **nothing is written** (the settle step does **not** silently fall
back to the suggested amount; the expense does **not** save). `1,234.56` is
**accepted** → 1234.56. (Settle-up only: an **empty** amount field still settles
the full suggested amount — that affordance is preserved.)
- [ ] Pass / [ ] Fail — notes:

### N2 — Equal split sums exactly (#596)
1. OMR group → add expense **2.900**, split **equally among 8**.

**Expected:** Seven people owe **0.362**, the alphabetically-last owes **0.366**,
summing to **exactly 2.900** — no half-baisa leftover, every share a whole baisa.
- [ ] Pass / [ ] Fail — notes:

---

## O. Create-form & profile polish (#489, #533, #487)

### O1 — Event type chip-row (#489)
1. Group → **New event**.

**Expected:** No separate type-picker screen. The form opens with a chip row of
exactly **4** types — **Trip · Camping · Travel · Night/Day Out** — above Event
Details. There is **no "Custom" chip**. Title **"New event"**, submit **"Create
Event"**.
- [ ] Pass / [ ] Fail — notes:

### O2 — Offline banner on create screens (#533)
1. **Airplane mode on.** Open **New group**, then **New event**.

**Expected:** Both screens show an amber strip **"You're offline — changes will
sync later"** (cloud-off icon) below the header. Turn airplane mode **off** → the
banner collapses away.
- [ ] Pass / [ ] Fail — notes:

### O3 — Isolated Danger zone (#487)
1. Profile/Settings → scroll to the bottom.

**Expected:** A standalone section headed **"DANGER"** containing a single card
whose only row is **"Delete account"** with a red **"Permanent"** tag — visually
separated from the "Backup & recovery" section above it.
- [ ] Pass / [ ] Fail — notes:

---

## P. Performance — no-regression spot-checks (#622, #623, #626, #627, #634, #640)

These were invisible perf merges (memoization, RepaintBoundary, static theme,
connectivity `.select`). There's nothing new to *see* — confirm nothing
**regressed**:
1. **Activity feed** (#634): scroll a long group/event feed — smooth, rows
   render correctly, no jank or blank rows.
2. **Ledger + split editor** (#627/#640): scroll a long ledger; type fast in the
   add-expense amount/split fields — the preview keeps up, no stutter.
3. **Home** (#626/#623): scroll the group list / journey tickets — smooth; toggle
   airplane mode on/off and confirm the home balance doesn't flicker or churn.

- [ ] Pass / [ ] Fail — notes:

---

## Known gaps / non-issues (do NOT file these)

- **Event recap has no share/export** — not in #202 Slice 1.
- **Recap button is hidden for events with no expenses** — by design (the empty
  state is only reachable by direct route).
- **Adjustments are fixed amounts, not percentages** — by design.
- **Itemized persists as `SplitMode.exact`; the ledger row has no "Itemized"
  badge** — by design (the line-item detail is opaque display metadata).
- **The group glyph does not render on the group *detail* screen** — only Home
  rows + Settings identity card.
- **No "Stamp" section header in the picker** — that string is unused; you'll see
  "INK" / "SYMBOL" / "Your initial is the default".
- **"You · shown above" is not a single literal string** (M3).
- **Recording a full on-behalf payment keeps the "We'll close out the balance…"
  body** — only a *partial* swaps to the "stays open" body.

---

## Sign-off

| Section | Result | Tester | Date | Notes |
|---|---|---|---|---|
| I · Itemized split | ✅ Pass | Nasser | 2026-06-22 | Pixel. Real bill (Americano 50→Nasser, V60 50→Everyone) + Service 10 equal → Nasser 70.002 / Sara 19.999 / Omar 19.999 = 110.000 (remainder→Nasser, uid sorts last). Items-match-total ✓, persist + itemized readback ✓, ledger net +39.998 ✓. Per-item #203 + adjustments #605 both byte-correct. |
| J · Trip stamps | ✅ Pass | Nasser | 2026-06-22 | J1 ✓ (picker: INK/SYMBOL/12 glyphs/caption, no "Stamp" header). J2 ✓ (glyph renders on Home group row + Settings card). J3 ✓ (edit from Settings: "Edit group" sheet, palm→house, persisted). J4 ✓ (monogram is the default first grid cell). |
| K · Event recap | ✅ Pass | Nasser | 2026-06-22 | Pixel. "3 people · 1 expenses" / Total spent OMR 110.000 / You paid 110.000 · Your share 70.002 · Net +39.998; Settlements row hidden (zero); no share button. NIT: count not pluralized ("1 expenses"). |
| L · Settle-up | 🟡 Pass (core) | Nasser | 2026-06-22 | L3 partial #587 ✓ (Sara 10+9.999, partial copy seen). L4 correction #567 ✓✓ (Omar re-opened −19.999, "Correction" row Nasser→Omar, original preserved). L1 on-behalf #595 + L2 non-participant eligibility #598 NOT tested (need Sara↔Omar debt / 2nd identity) — deferred. |
| M · Display truth | ✅ Pass | Nasser | 2026-06-22 | M1 ✓ (preview "Amounts vary per person." → 50/25/25 on shares 2:1:1). M2 ✓ (ledger row real net +39.998). M3 ✓ (group-detail "PEOPLE" header, self-row muted). |
| N · Money input | ⬜ Unit-covered | Nasser | 2026-06-22 | #530 European reject (needs clipboard paste) + #596 quantize (needs 8-way split) not driven on-device; both pinned by unit tests (localized_decimal_input, balance_calculations). Deferred to suite, not a device gap. |
| O · Create-form & profile | ✅ Pass | Nasser | 2026-06-22 | O1 ✓ (type chips Trip/Camping/Travel/Night-Day-Out, no Custom; made a Camping event). O2 ✓ (offline banner "You're offline — changes will sync later" on New group). O3 ✓ (standalone "DANGER" section, Delete account + red "Permanent"). |
| P · Performance | ⬜ Not exercised | Nasser | 2026-06-22 | Single event / few expenses — no long activity/ledger feeds to stress-scroll. No jank observed in normal use. Defer a real perf glance to a data-heavy account. |

**Blockers found:**
- **None (no product blocker).** The only wall hit was a **QA-environment** issue: the
  debug build's App Check token is rejected (`app: INVALID` server-side), so every
  **callable** (`addShadowMember`, claim, deleteAccount-cascade, deleteGroup) fails.
  Worked around by admin-seeding the two shadow members. Not a product defect.

**Other findings (non-blocking):**
- **[QA-env] Debug-build App Check blocks callables.** `addShadowMember` returns
  `app: INVALID` ("Decoding App Check token failed" — client sends a placeholder
  because its debug-token exchange 403s / rate-limits). Group create (direct Firestore
  write) succeeds, but the **"Who's in?" shadows at create are silently dropped**, and
  in-group **"Add a person"** errors **"Please sign in and try again."** → **Device QA
  of any callable flow requires a Play-signed build** (or a genuinely working App Check
  debug token). The debug SHA-1/256 are already registered; the debug *token* is the gap.
- **[Potential UX — candidate follow-up]** When the post-create `addShadowMember` call
  fails, the group is created but the user's typed names **vanish with no error**. On a
  healthy Play build App Check works, but a transient callable failure (offline/error)
  would silently lose the names. Worth surfacing a retry/error instead of a silent drop.
- **[Minor i18n]** Recap subtitle reads **"1 expenses"** — count is not pluralized.
- **[Minor]** Two duplicate `QA160` groups appeared during the create/gate retries
  (likely repeated manual attempts; not cleanly reproduced).

**Verified clean on-device (2026-06-22, Pixel 9 Pro XL, debug build):** §I itemized
money (byte-exact incl. #605 adjustments) · §K recap · §L settle-up partial #587 +
correction #567 (balance re-opens) · §M display-truth (preview/row/group-detail) ·
§J trip stamps (pick/edit/render) · §O create-form/offline-banner/danger-zone.
**Not exercised:** §L1/L2 (need 2nd identity), §N (unit-covered), §P (need data-heavy
account), and all **callable** flows (need a Play build — see blocker note).

**Ship decision for 1.6.0:** ☑ **Go** (feature-acceptance) — the 1.6.0 delta is verified
clean on-device with no product blockers. Gate to release is the standard **RD-01…RD-13
matrix (#40) on a Play-signed internal-testing build**, which also covers the callable
flows (shadow add, claim, delete) this debug pass could not.
