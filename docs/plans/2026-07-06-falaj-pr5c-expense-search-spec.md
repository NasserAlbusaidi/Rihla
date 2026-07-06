# PR-5c (Option C / #923) — Full **Expense** Search via Server-Maintained Token Index — DRAFT SPEC

**STATUS: DRAFT — PRE-GATE.** Not yet run through `/run-the-gate`. This spec touches a new Cloud Functions trigger, `security/firestore.rules`, a new schema (`searchIndex` docs with a read-path and a write-path), and routing-adjacent client surface — **all four Gate categories**. No code before a clean fresh-context round (rubric + orthogonal adversary, both P1-clean same round). Refs #923, #900. Follows the house style of `docs/plans/2026-07-05-falaj-pr5b-search-spec.md`.

---

## Problem (friction #3, the part PR-5b deferred)

PR-5b shipped global `/search` over **groups + events only** (client-side, over already-warm `groupEventsProvider` streams). It deliberately did **not** search expense text — its own scope note: *"Full expense search remains Option C — needs a server index … do NOT hand-roll a client full-scan and do NOT fan out live expense listeners. The friction-#3 tap-table claim ('find old expense 4→2') belongs to Option C, not v1."*

So today, finding an old expense still means: recall the group → recall the event → open the event → open the ledger → search within it (4+ taps, and you must already remember *which* trip it was on). #923 is that job: **type a word, land on the expense's edit screen in ~2 taps, across all groups and all events (including long-settled/closed ones).**

---

## Chosen option + why

**Winner: Option A — denormalized token index in a server-only sibling subcollection, maintained by a Cloud Function trigger, queried with `array-contains`.**

### The honest judge picture (flagged, not buried)

Three judges scored three dossiers (A token-field / B external-index / C client-bounded):

| Lens | 1st | 2nd | 3rd |
|---|---|---|---|
| money-&-data-integrity | C (9) | A (8) | B (3) |
| solo-dev-ops-&-cost | C (8) | A (6) | B (3) |
| user-value-&-search-quality | B (7) | A (6) | **C (3)** |

Point totals tie A and C at 20; B trails at 13. **This is a genuine split, and I am not going to paper over it.** Two lenses rank C first — but *both concede in their own dossier* that C (a fixed recency-N client fan-out) **structurally cannot find the old, long-settled, "forgotten" expense**, which is *precisely* the #923 job (C dossier §7.3, §8: *"an old expense in a closed, long-settled event is definitionally outside any recency-bounded window cheap enough to justify"* → it delivers *"find a **recent** expense fast,"* a materially different, smaller claim). The one lens aligned with the actual issue requirement (user-value) ranked C **last** for exactly this reason.

**#923 as filed is an index-design task** — its text says *"Needs a server-side index … Blocked on a design round for the index shape + Firestore cost model,"* and the task constraints (cheap rules-validated fields, `export {} from` triggers, no per-IP throttle) only bite when you build a server index. C answers a re-scoped question, not this one. **B is ranked last by two judges** and is disqualified for this codebase's core invariant: it relocates the entire multi-tenant boundary for expense text *out of `firestore.rules`* into one hand-maintained TypeScript membership filter (cross-tenant-leak class), ships a display money copy off-platform to a first-ever third-party subprocessor, and introduces the first vendor credential in Functions runtime (grep-confirmed: zero `defineSecret`/Secret Manager usage in `functions/src` today).

**A is the Condorcet-safe pick: never ranked last by any judge, it is the only option that (a) actually finds old expenses [the job], (b) is $0 forever with no vendor [ops], (c) has zero client-forgery surface and touches zero rules-expression budget on the hot write path [integrity].** The graft consensus across all three judges is explicit: *"if you build a server index, build it THIS way — off-doc sibling, `allow write: if false`, Admin-SDK-only trigger; NEVER an on-doc `searchTokens` field."* That is Option A.

→ **See Open Question 1** for the one scope decision the human must still make: ship A now, or ship C's cheap client layer *first* as a stopgap and defer A. This spec designs A.

### Grafted ideas adopted (cited to source)

- **From B →** the absolute contract that **money never enters the index as a computed value** and `splitDistribution`/`splitExplanation` never leave Firestore — the index is oracle-invisible, same contract as `splitExplanation` (CLAUDE.md). The tap **always** re-reads the LIVE expense doc on `EditExpenseScreen`; the index is a *pointer + text label*, never a source of truth.
- **From B →** a **reconciliation scheduled Function** (mirroring `scheduled/balanceReconciler.ts`) to catch silent trigger-delivery drift — A's standalone dossier proposed none, and both integrity + ops judges flagged silent index drift as its top risk.
- **From C →** the **"results may be incomplete (offline)" badge**, reusing the `GroupBalancesOnce.failedEventIds` → `balance_hero_card.dart` partial-result precedent, instead of a silent empty state (a silent empty in a money app reads as *"you deleted my expense"* — the #244 class).
- **From C →** reuse of the existing **`_ResultRow` shape + deep-link push target** (`/group/$gid/event/$eid/ledger/edit/$expenseId`, the exact `ledger_search_sheet.dart` target), plus **400 ms debounce + session-scoped result cache** on the query side.
- **From A (self) →** the **cross-language golden-fixture parity test** (shared JSON `{input, expectedTokens}` asserted by BOTH a Jest test and a Dart test, CI-blocking on either side drifting) — the load-bearing guard for A's one real weakness.
- **From A (self) →** **soft-delete = DELETE the index doc** on `isDeleted false→true` (cheapest op, respects the soft-delete invariant, keeps deleted expenses out of results).

### Refinements this spec makes *over* Dossier A (verified against live rules)

1. **Index lives at the GROUP level, not nested under the event.** Dossier A proposed `groups/{gid}/events/{eid}/searchIndex/{expId}` queried via `collectionGroup('searchIndex')`. But `collectionGroup` rule-matching does **not** bind through the `{module}` *path-variable* wildcard (`firestore.rules:662`, `match /{module}/{docId}`), and a dedicated collection-group rule would need `match /{path=**}/searchIndex/{docId}` — awkward. **Instead: `groups/{gid}/searchIndex/{expenseId}`** (event id carried as a field). One direct subcollection `.get()` per group covers all that group's events — the **exact O(G) fan-out shape PR-5b already established**, no `collectionGroup`, no composite index gymnastics. Resolves the integrity judge's "sibling doc falls under the `{module}` wildcard" overlap concern outright.
2. **No new composite index needed.** A single `where('searchTokens', arrayContains: term).limit(N)` with **no `orderBy`** is auto-indexed (single-field array-contains). Ranking (recency) is done client-side after cross-group merge. (Contrast Dossier A's collection-group `(groupId, searchTokens CONTAINS)` composite — eliminated.)
3. **Rules change is ONE token added to an existing allow-list**, not a new match block (see §Rules).

---

## Index shape (exact)

`groups/{gid}/searchIndex/{expenseId}` — doc-id-keyed 1:1 with the live expense, written **only** by the Admin SDK trigger:

```jsonc
{
  "expenseId": "exp_9f2a",     // == doc id; the pointer
  "eventId":   "evt_c31b",     // to build the deep-link target
  "groupId":   "grp_44e0",     // redundant-but-cheap; enables a flat query if ever needed
  "searchTokens": [            // normalized; see §Arabic. array-contains match target.
    "dinner","din","joe","restaurant","food","طعام","عشاء"
  ],
  "descriptionSnippet": "Dinner at Joe's",   // DISPLAY-ONLY row label (raw, un-normalized). ≤ the validFreeText cap.
  "categoryId": "food",                        // for the row icon/label via categoryIconForId/categoryNameForId
  // --- OPEN QUESTION 2: carry a display amount, or not? ---
  // "amountMinor": 125000, "currency": "OMR",  // DISPLAY-ONLY if kept; re-rendered via RAmount, NEVER math.
  "updatedAt": "2026-07-06T18:22:00.000Z"
}
```

**Never in this doc:** `splitDistribution`, `splitExplanation`, `payerParticipantId`/payer identity, `amount` as anything a balance path reads. Free-text token sources are exactly two fields (verified against `expense_model.dart`): **`description`** (`:31`) and **`note`** (`:48`). `categoryName` is **never persisted** (`toFirestore` omits it, `:238-266`) — so the **category token must be generated at write time from `categoryId`**, in **both** shipped locales (EN + AR), because the trigger has no notion of the reading device's locale (an Arabic reader must find an English-created "Groceries" by typing "بقالة" and vice-versa).

---

## Write path — trigger + backfill

### Trigger (`functions/src/triggers/expenseSearchIndexer.ts`, new)

Modeled directly on `expenseAuditLogger.ts` (`onDocumentWritten` at `:188`, same path `groups/{gid}/events/{eid}/expenses/{expenseId}`, same anti-self-retrigger discipline — it writes to a **disjoint** collection so it can't re-fire itself; the audit logger writes `activity_logs/${event.id}`, we write `groups/{gid}/searchIndex/{expenseId}`).

```ts
const SEARCH_CONTENT_KEYS = ['description', 'note', 'categoryId', 'isDeleted'] as const;

export const expenseSearchIndexer = onDocumentWritten(
  'groups/{gid}/events/{eid}/expenses/{expenseId}',
  async (event) => {
    const before = event.data?.before.exists ? event.data.before.data() : undefined;
    const after  = event.data?.after.exists  ? event.data.after.data()  : undefined;
    const { gid, eid, expenseId } = event.params;
    const ref = getFirestore().doc(`groups/${gid}/searchIndex/${expenseId}`);

    if (!after) { await ref.delete().catch(() => {}); return; }                       // hard delete (rare)
    if (SEARCH_CONTENT_KEYS.every(k => deepEqual(before?.[k], after[k]))) return;      // diff-gate: money-only edits no-op
    if (after.isDeleted === true) { await ref.delete().catch(() => {}); return; }      // soft-delete → drop from index

    await ref.set({
      expenseId, eventId: eid, groupId: gid,
      searchTokens: buildSearchTokens(after.description, after.note, after.categoryId), // §Arabic; BOTH locales for category
      descriptionSnippet: (after.description ?? '').slice(0, 280),
      categoryId: after.categoryId ?? null,
      updatedAt: event.time,
    });                                                                                // merge:false — full overwrite
  },
);
```

**Diff-gate matters for cost:** a money-only edit (amount/payer/split) changes none of `SEARCH_CONTENT_KEYS`, so the trigger fires-but-no-ops (0 extra Firestore write). Registered per the mandatory `export {} from` pattern (`functions/src/index.ts` — all exports are re-exports; a bare `export const` is invisible to `tool/list_expected_functions.sh` and would escape the deploy-drift check):

```ts
export { expenseSearchIndexer } from './triggers/expenseSearchIndexer';
```

### Category tokens in both locales

`ledger_categories.dart` (`categoryNameForId`, `:53`; `kCategoryIds`, 10 ids, `:15`) is Dart-only. The trigger needs a **small static TS map** `categoryId → {en, ar}` (20 strings, sourced from the `categoryFood…categoryOther` ARB keys). **Drift guard:** a Jest test asserts the TS map's keys `== kCategoryIds` exactly (fails CI if a category is added to the Dart SSOT but not the TS mirror). → **Open Question 4** on static-map vs codegen-from-ARB.

### Backfill (`functions/scripts/backfillSearchIndex.ts`, new, one-off, manual)

`collectionGroup('expenses').where('isDeleted','==',false)` (the `(isDeleted, createdAt)` collection-group index already exists — used by `getExpenses`, `expense_service.dart:107`), computing tokens with the **same imported `buildSearchTokens`** (never a second copy), `.set()`-ing each `groups/{gid}/searchIndex/{expenseId}`. At scale (5,000 expenses) = seconds, one run. **Deploy ordering (discipline, not architecture):** deploy rules+trigger FIRST (new writes stay current) → run backfill SECOND (catches the existing corpus) → ship client PR4 THIRD. A search before backfill completes is silently incomplete-for-old-expenses — never ship the client first.

### Reconciler (`functions/src/scheduled/searchIndexReconciler.ts`, new — graft from B)

Mirrors `balanceReconciler.ts`: periodically spot-diffs a sample of live-expense count vs `searchIndex` doc count per group; logs/alerts the solo dev on drift beyond a threshold (idempotent trigger means a stale doc self-heals on the next real edit, but a delivery failure otherwise degrades silently). `export { searchIndexReconciler } from './scheduled/searchIndexReconciler';`.

---

## Rules impact + expression-budget note

**Zero touches to `validExpenseBase` / `validExpenseCreate` / `validExpenseUpdate`.** The near-1000-expression event/expense update path (`firestore.rules:201-217`, #723) gains **zero** expressions — the whole reason A wins the integrity axis. The trigger runs Admin SDK (bypasses rules).

The searchIndex doc lives at the **group** level, so it does **not** fall under the event `{module}` wildcard. Add a small dedicated block, sibling to the group-member reads:

```diff
  match /groups/{gid} {
    // … existing member/event reads …
+   // #923 — expense search index. Written ONLY by the expenseSearchIndexer
+   // trigger via the Admin SDK (rules bypassed). Members READ; no client
+   // may create/update/delete — no forgery surface (the whole doc is
+   // server-only; strictly simpler than a client-writable server-stamped field).
+   match /searchIndex/{docId} {
+     allow read:  if isGroupMember(gid);
+     allow write: if false;
+   }
  }
```

**Expression budget:** the only new predicate is `isGroupMember(gid)` on a `searchIndex` **read** — a separate, cheap match evaluated only when a searchIndex doc is read, never on any expense write. `allow write: if false` = no forgery surface at all (stronger than any client-writable field). **Verify at the Gate:** confirm `isGroupMember` here binds `gid` from the group path (not an event-scoped variant) and that no recursive `/{path=**}` rule elsewhere accidentally grants a wider searchIndex write.

---

## Client query + UI plug-in points

All plug-in points verified live in `lib/features/search/`:

- **Provider (new, `lib/features/search/providers/expense_search_provider.dart`):** a debounced (400 ms, min 2 chars) family/AsyncNotifier that, per group in `userGroupsProvider`, fires **one-shot** `groups/{gid}/searchIndex.where('searchTokens', arrayContains: term).limit(N).get()` (N e.g. 8/group), merges across groups, sorts by `updatedAt` desc client-side, caps ~20 rows. **One-shot `.get()`, NEVER a live listener** — opening a per-group listener on searchIndex reopens the O(G) *listener* class PR-5b bounded to zero (Judge 3 flagged Dossier A's "same shape as events" listener claim as understated: events listeners are already mounted, searchIndex ones would be net-new). Session-cache the merged raw result for the life of the `/search` route; re-filter in-memory on keystrokes, refetch only on term change past the debounce.
- **UI:** extend `search_results.dart` (`SearchResults` `:35`) with a new **"Expenses"** `SectionHeader` (`searchSectionExpenses`) rendering `_ExpenseRow` reusing the `_ResultRow` shape (`:211`) — icon `categoryIconForId(categoryId)`, title `descriptionSnippet` (fallback `categoryNameForId`), subtitle **event · group** (cross-group disambiguation, mirroring `_EventRow` `:158`), trailing display amount **iff** OQ2 says carry it. Forward chevron = `DirectionalIcon` (RTL). 
- **Deep link:** tap → `context.push('/group/$gid/event/$eid/ledger/edit/$expenseId')` — the exact live target from `ledger_search_sheet.dart` (`:294` per grounding); `EditExpenseScreen` re-reads the LIVE doc (index is a pointer). No new route.
- **Offline (graft from C):** track which per-group `.get()`s failed/returned empty due to offline-cache-miss; render the reused **"results may be incomplete (offline)"** affordance (`balance_hero_card.dart` precedent) rather than a silent empty. searchIndex has no other reader, so its offline cache is thin — surface it, don't pretend.

**Callsite classification (INBOUND/OUTBOUND/BOTH):**

| Surface | Class | Note |
|---|---|---|
| `searchTokens` (index write, trigger) | **OUTBOUND** | server-computed from expense fields; never read back into money math |
| `descriptionSnippet`, `categoryId` (index) | **INBOUND** | display-only row label/icon; never persisted onward |
| `amountMinor`/`currency` (index, if OQ2=yes) | **INBOUND** | display-only, re-rendered via `RAmount`, **never** a balance input — same oracle-invisible contract as `splitExplanation` |
| index doc read → `_ExpenseRow` | **INBOUND** | pure display |
| tap → `EditExpenseScreen` | **BOTH** | but it re-reads the LIVE expense doc; the index value never feeds the edit write |
| client query `term` tokenization | n/a | must byte-match the TS `buildSearchTokens` (see §Arabic) |

The **only** OUTBOUND on the whole feature is the trigger's `searchTokens`, and it is derived server-side from already-persisted fields — no display-formatted string is ever persisted (the §Verification-principle-1 trap).

---

## Arabic normalization plan

`matchesSearchQuery` (PR-5b's `search_match.dart`, `contains(toLowerCase)`) is **insufficient** for expense free-text: it never folds hamza/alef/taa-marbuta/diacritics and does pure substring (no word-order tolerance). Expense text is longer and more variable than a group name, so the miss rate is material. A **shared normalization pipeline**, implemented **twice byte-identically** (TS trigger + Dart client query):

1. Unicode-normalize to **NFC** (JS `.normalize('NFC')`; Dart needs an explicit pass — `unorm_dart` or a small hand-rolled one).
2. Strip tashkeel/diacritics `\u064B-\u0652` + tatweel `\u0640`.
3. Fold alef forms `أ إ آ ٱ → ا`.
4. Fold alef maksura `ى → ي`.
5. **Taa marbuta `ة`:** index BOTH the raw and a `ة→ه` variant as two tokens (do NOT hard-fold — it's a distinct letter). → OQ3.
6. Lowercase (no-op for Arabic; needed for mixed Latin).
7. Whitespace/punctuation tokenize → whole-word tokens.
8. Bounded prefixes per word (len 2..min(len,12)) for search-as-you-type, with a **hard per-field word cap and per-word prefix cap** (a 280-char no-whitespace `note` is rules-legal, `validFreeText` `firestore.rules:25-30` — cap token count to avoid an unbounded array).

**The load-bearing guard (graft, non-optional):** a **cross-language golden-fixture parity test** — a shared JSON of `{input, expectedTokens}`, asserted by a Jest test (`functions/`) AND a Dart test (`test/`), CI-blocking. Without it the two normalizers drift silently and Arabic search under-matches with no error — the #244-class invisible-degradation, and the standout risk of this whole option (both integrity + ops judges named tokenizer drift as A's top failure mode).

---

## Cost model (verified 2026-07-06; $ figures from Firestore public pricing)

Free tier resets daily: 50k reads / 20k writes / 20k deletes / 1 GiB. Blaze: reads ~$0.06/100k, writes ~$0.18/100k, deletes ~$0.02/100k.

| Event | Extra Firestore ops | Extra Fn invoke |
|---|---|---|
| Create expense | +1 write (index doc) | +1 |
| Content edit (desc/note/category) | +1 write | +1 |
| Money-only edit (amount/payer/split) | **+0** (diff-gate) | +1 (no-op) |
| Soft-delete | +1 **delete** (cheaper) | +1 |
| Search query | reads = hits returned per group (`limit N`) | 0 |

| Scale | Extra writes/mo | Search reads/mo | Storage | **$/mo** |
|---|---|---|---|---|
| A: 10 grp / 5,000 exp / 300 searches | ~600 (vs ~600k free) | ~9k worst (vs ~1.5M free) | ~1.5 MB | **$0.00** |
| 10×: 100 grp / 50,000 exp / 3,000 searches | ~6,000 | ~90k (6% of free) | ~15 MB | **$0.00** |

**Firestore-native cost is not a decision factor at this app's scale — it's $0 either way.** The real costs are engineering (TS↔Dart tokenizer parity, backfill discipline, reconciler) and the product-fit ceiling of `array-contains` (§Non-goals), not dollars. (Contrast B's unconditional $22–30/mo vendor floor for two of three named vendors, and C's 10×-scale breach of the 50k/day free tier.)

---

## PR split (each leaves the tree green)

- **PR1 — backend, dormant.** `expenseSearchIndexer.ts` + shared `buildSearchTokens` (TS) + TS category-name mirror + drift-guard test + `index.ts` export + the `searchIndex` rules block. Zero client change; deployable and inert. Green: functions Jest (emulator) + `firestore-rules-publish-readiness.test.ts`. Confirms zero touch to `validExpenseUpdate`.
- **PR2 — backfill + reconciler.** One-off `backfillSearchIndex.ts` (manual, documented) + `searchIndexReconciler.ts` scheduled fn + `index.ts` export. Green: reconciler unit test.
- **PR3 — Dart tokenizer + parity harness.** `search_tokenizer.dart` (Dart port) + the shared golden-fixture JSON + Jest and Dart assertions. Landed and green **before** PR4 wires the UI (repo's test-first discipline). Green: both test suites.
- **PR4 — client (Gate-category, re-run `/run-the-gate`).** `expense_search_provider.dart` (debounced one-shot fan-out + session cache) + "Expenses" section in `search_results.dart` reusing `_ResultRow` + deep link + offline-incomplete badge + EN+AR l10n keys. Green: `test/features/search/` widget + nav tests; `flutter analyze`; theme-purity.

Each PR independently green and revertable ("one PR does one thing"). Deploy sequence across PRs: **rules+trigger (PR1) → backfill (PR2) → client (PR4)**. Per CLAUDE.md ("no real users yet → server changes deploy freely"), no client-compat gating.

---

## Non-goals (explicit)

- **No typo/fuzzy/mid-word substring search.** `array-contains` over precomputed word-prefixes is a hard ceiling — "resturant" (typo) and "staurant" (mid-word) return nothing. If the acceptance bar demands real full-text, that is a re-tokenization migration, not an increment (§OQ1).
- **No relevance ranking beyond client-side recency sort.**
- **No `SplitMode.itemized`; the server never reads `splitExplanation` or any money field** (CLAUDE.md contract). The index is oracle-invisible.
- **No client full-scan of `expenses`, no live expense listeners, no `collectionGroup('expenses')` scan** (the #104 listener class + the collection-group billing/privacy footgun).
- **No change to `validExpenseBase`/`validExpenseUpdate`/`MoneySerializer`.** No second money representation.
- **No guaranteed offline expense search** — thin cache by construction; surfaced honestly via the incomplete badge, not silently.
- **Not the Option-C client-bounded design** (recency-N fan-out) — see OQ1.

---

## Open questions (human decides)

1. **THE scope decision — A now, or C-first-then-A?** Two judges preferred the cheap client-bounded Option C on cost/ops/integrity-simplicity, but C **structurally cannot find the old/forgotten expense that is the #923 job** (its own §7.3; the requirement-aligned user-value judge ranked it *last*). The graft consensus was *"ship C's zero-infra client layer now as a stopgap, defer the server index."* **Decide:** (a) build A per this spec (solves the stated job, $0, ~4 PRs); or (b) ship C first (1 PR, "recent expense fast") and re-scope #923's "old expense" claim to a later A. Do not let convergence toward "smaller is safer" quietly redefine what #923 asked for.
2. **Carry a display amount in the index doc?** Text-only is integrity-safest (the money-integrity judge's preference — no money copy off the expense doc at all); a display-only `amountMinor`+`currency` (re-rendered via `RAmount`, never math) makes search rows far more disambiguable. Default in this spec: **flagged optional, leaning text-only for v1**.
3. **Taa-marbuta handling** (dual-token vs hard-fold) and **prefix-token generation** (whether to emit prefixes at all vs whole-word-only) — precision vs index-size/token-count. Needs a call with the Arabic normalization pipeline.
4. **Category-name TS mirror:** hand-maintained static map (+ drift-guard test) vs codegen from the ARB files. Static map is simpler now; codegen removes the drift class entirely.
5. **Reconciler policy:** sampling rate, drift threshold, and alert channel for a solo dev (reuse `balanceReconciler` cadence?).
6. **Offline fork (Dossier A §6):** accept one-shot `.get()` + incomplete badge (thin cache, this spec's default), or open a *bounded* per-group live listener to warm the offline cache — the latter is net-new O(G) listeners (Judge 3's correction to A's "same as events" claim), not free. Default: **one-shot + honest badge.**

---

**Verification note (per the Operating Contract, reported out loud):** anchors checked live this session — `expenseAuditLogger.ts` `onDocumentWritten` at `:188` writing a disjoint `activity_logs` path (the trigger precedent); `functions/src/index.ts` is all `export {} from` re-exports (deploy-drift extractor requirement); `firestore.rules:969` `{module}` read allow-list is `['expenses','settlements','activity_logs']` and its writes are module-gated to `'expenses'`/`delete:if false` (so a client cannot write a group-level `searchIndex` doc — no forgery surface); `expense_model.dart` free-text fields are `description`/`note`, `categoryName` is never persisted (`toFirestore` `:238`); `ledger_categories.dart` `kCategoryIds` = 10 ids, `categoryNameForId` `:53`; `expense_service.getExpenses` uses the existing `(isDeleted, createdAt)` index (`:107`); `lib/features/search/` has `SearchResults`/`_ResultRow`/`_EventRow`/`SectionHeader` to extend. **This is a DRAFT and has NOT been through the Gate; the rules-binding of `isGroupMember(gid)` in the new block and the absence of any wider `/{path=**}` searchIndex write grant must be re-verified fresh-context before implementation.**
