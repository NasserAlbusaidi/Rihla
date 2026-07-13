# #1216a — Name format-char VALIDATION Implementation Plan (split from #1216 after Gate r2)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reject U+202E-class bidi controls and zero-width characters in display-name validation, byte-aligned across the Dart client, `firestore.rules`, and the two Functions NAME validators, with an invisible-name floor — WITHOUT touching any free-text validator.

**Architecture:** One shared reject-set `K` + visible-char floor, applied at: `name_validators.dart` (names only), rules `isValidDisplayName` (single-regex fold, net-zero `matches()` growth) + `displayNameMapValuesAreValid`, `functions/src/callables/shared/displayName.ts`, `functions/src/callables/joinGroupByInviteCode.ts`. Plus `sanitizeActorName`'s strip/totality extended so its co-batched activity rows keep passing the tightened rules (#1140 batch-veto guard).

**Split provenance:** #1216 spec v2 went through Gate r1+r2 (two independent pairs). The VALIDATION half below was verified clean by the r2 rubric reviewer (hand-traced vectors, RE2-legality, exactly-two-name-validators claim, sanitizer totality, transitive `recordSettlement` name coverage); the render-isolation half split into `2026-07-13-1216b-bidi-isolation.md`. This spec still requires its own clean Gate round before implementation.

**Issue:** Refs #1216 (partial — the `Refs` must be in the COMMIT MESSAGE too, never `Closes`; #1216 closes when 1216b also lands). Gate category: rules + Functions validation. **DEPLOY DEFERRED: rules/Functions changes MERGE now, deploy ONLY at the next release ceremony (users live — CLAUDE.md deploy policy).**

---

## The character policy

**REJECT set `K` (identical across layers; ALWAYS escapes in source/tests, never raw invisibles):** U+00AD, U+200B, U+200E, U+200F, U+202A–U+202E, U+2060–U+2064, U+2066–U+2069, U+FEFF.

**ALLOW: U+200C (ZWNJ), U+200D (ZWJ)** — orthographically required in Persian/Kurdish and inside emoji ZWJ sequences; joiners, not bidi controls; emoji/astral names are legal today.

**Visible-char floor:** the name must contain ≥1 char that is not in `K`, not whitespace, and not ZWNJ/ZWJ.

**Cross-engine whitespace note:** the floor's "whitespace" is RE2/JS `\s` server-side while Dart implements the floor via Unicode `trim()` — an exotic-whitespace-only name (e.g. NBSP) may be client-REJECT / rules-ACCEPT. Client-stricter = the SAFE direction (no PERMISSION_DENIED for a client-validated write). Gate r2 caveat: rules `.trim()` semantics are unverified — when pinning V16 in the emulator, record the ACTUAL rules verdict; either outcome is safe-direction, the test documents which.

## Verified context (Gate r1+r2 verified against live code)

- Client: `lib/core/utils/name_validators.dart:28-33` `_hasControlChar` (C0+DEL) is shared by `displayNameValidationError` AND `freeTextValidationError` — ONLY the name path gains new checks.
- Rules: `isValidDisplayName` (~:38-44, charset matches :43); `displayNameMapValuesAreValid` (~:53-59, join-charset :56, per-value non-space :58). `isValidDisplayName` call sites: :332/:368/:475/:516/:1098/:1117/:1197 — single chokepoint, edit the function body only. `validFreeText` (:25-30) UNCHANGED.
- **Functions NAME validators — EXACTLY TWO:** `shared/displayName.ts:8` (`normalizeRequiredDisplayName`; used transitively by `recordSettlement.ts` `nullableDisplayName` :104/:523 for payerName/recipientName/actorName, and by `addShadowMember`/`requestClaimShadow` — no third server name-write path, r2-verified) and `joinGroupByInviteCode.ts:70`. **DO NOT TOUCH** `shared/settlementCorrection.ts:34` or `recordSettlement.ts:86-96 nullableFreeText` — both are NOTE validators whose comments say "Mirror firestore.rules validFreeText"; tightening them hard-fails money callables on legit pasted notes and desyncs from unchanged rules.
- **`sanitizeActorName`** (`group_activity_service.dart:118-141`): contract "every input → passes rules `isValidDisplayName`"; output co-batched with money/lifecycle mutations (#1140; rules :1197 enforces). Must strip `K` (:125 regex), mirror the floor, extend the totality-guard regex (:133).
- Localized error copy: reuse `DisplayNameValidationError.controlCharacter` → `nameValidationControlChars`. No new enum case, no ARB changes.
- `setDeviceName`/`seedDeviceName` (settings_provider.dart:114/:148) re-validate through this validator → no poison enters `propagateDisplayName`; a legacy poisoned name silently won't seed (fail-safe).
- #196 collision key (`trim().toLowerCase()`) reads raw names — no interaction (r2-verified).

## Rollout / old-client compatibility (users live)

Client ships next release; rules + the two TS tightenings MERGE now, DEPLOY at that release (`tool/pending_deploy.sh`; `backend-deployed` tag is truth). Stale clients holding `K`-poisoned member names post-deploy: their event-create batch can be rules-denied via the activity row — accepted, `K` occurs only in crafted names. Existing poisoned docs: client edits fail until cleaned (Admin SDK path) — and note the breadth (Gate r3): `displayNameMapValuesAreValid(participantNames)` in `validEventBase` (rules :483) is NOT diff-gated, so a legacy event holding a poisoned participantNames value fails EVERY event-doc update (name/date/close/roster), not just create; bounded and recoverable (expenses are a separate subcollection; rename-away-from-poison passes; Admin SDK for shadows). A stale client's queued poisoned-name write replaying post-deploy is rules-rejected (silent per #412) — accepted. Verified non-veto paths (Gate r3): `recordSettlement`'s actorName derivation try/catches the tightened validator and falls back to input-validated names/'Someone' (:519-528); `claimShadowEngine` writes via Admin SDK (bypasses rules — legacy poisoned shadow claims still succeed).

**Accepted residuals (named, not fixed here):** a settle-up against a member whose STORED legacy name is K-poisoned hard-fails post-deploy (`recordSettlement` `nullableDisplayName` :101-108 throws on the client-echoed counterparty name; the recorder's OWN poisoned name already floors to 'Someone' via the :519-528 try/catch) — same crafted-names-only bucket, Admin cleanup path; if it ever bites a real user, the follow-up is mirroring the floor-to-'Someone' idiom in `nullableDisplayName`. ZWNJ/ZWJ homoglyph confusability ("Ali" vs "Al‌i" are distinct #196 collision keys, render near-identically — deliberate Persian/emoji tradeoff; revisit only with a joiner-folding proposal for the collision key); the reused `nameValidationControlChars` copy is unactionable for invisible chars (user can't see what to remove) — deliberate zero-ARB tradeoff.

## Non-goals

- No `\p{Cf}` blanket rejection (bans ZWNJ/ZWJ).
- No free-text tightening anywhere (client, rules `validFreeText`, TS `normalizeCorrectionNote` + `nullableFreeText` — byte-identical, pinned by tests).
- **No render isolation** — that's `2026-07-13-1216b-bidi-isolation.md` (independent files, no overlap).
- No TS validator dedup; no data migration.

---

### Task 1: Golden vectors (escaped notation — never raw invisibles, in the tests OR docs)

| # | input | verdict | why |
|---|---|---|---|
| V1 | `Ali` | ACCEPT | baseline |
| V2 | `Ali‮` | REJECT | RLO |
| V3 | `‭hack` | REJECT | LRO |
| V4 | `a⁦b⁩` | REJECT | isolate controls in names |
| V5 | `​​` | REJECT | ZWSP-only |
| V6 | `Ali​x` | REJECT | embedded ZWSP |
| V7 | `می‌خواهم` | ACCEPT | Persian ZWNJ |
| V8 | `\u{1F468}‍\u{1F469}‍\u{1F467}` | ACCEPT | emoji ZWJ sequence |
| V9 | `‍‌` | REJECT | joiner-only fails floor |
| V10 | `‍ ‌` | REJECT | joiners+ASCII-space invisible |
| V11 | `Bob﻿` | REJECT | BOM |
| V12 | `x­y` | REJECT | soft hyphen |
| V13 | `‎ltr` | REJECT | LRM |
| V14 | `عمر` | ACCEPT | plain Arabic |
| V15 | `Ali⁠` | REJECT | word joiner |
| V16 | ` ` (NBSP-only) | client REJECT / rules: record actual emulator verdict | safe-direction divergence doc |

**Plus a full-`K` iteration property test in Dart AND TS:** for every code point in `K`, `'Ali' + char` rejected — a dropped char in any copy has a failing test.

### Task 2: Dart validator (RED → GREEN)

`lib/core/utils/name_validators.dart`: export `kDisallowedFormatChars` — a **range-EXPANDED, per-code-point** string built from `\u` escapes (U+202A..202E as five chars, U+2060..2064 as five, U+2066..2069 as four — Gate r3: the constant feeds BOTH the RegExp class AND the full-K iteration test, which must enumerate code points) + `_disallowedFormatChar` RegExp + exported `isInvisibleOnlyName(String s)` = `s.replaceAll(RegExp('[‌‍]'), '').trim().isEmpty` (escapes, never raw joiners in source — same for the TS floor `/[^\s‌‍]/u`). **The K-check runs on `raw`, NOT `trimmed`** (Gate r3: Dart `trim()` strips U+FEFF, so a trailing-BOM name would false-accept client-side while rules reject it — the exact PERMISSION_DENIED this spec prevents; `_hasControlChar(raw)` at :54 is the precedent). New checks ONLY in `displayNameValidationError` (map to `controlCharacter`); `freeTextValidationError` byte-identical (pin: ZWSP-in-note stays ACCEPTED). Update the library doc comment (currently promises "every printable code point accepted"). Table-driven V1–V16 + full-K iteration in `test/unit/name_validators_test.dart`. RED first; capture output.

### Task 3: `sanitizeActorName` (RED → GREEN)

`group_activity_service.dart`: extend strip regex (:125) with `K` (import the exported Dart constant — ONE source of truth), extend totality-guard regex (:133) identically, add `isInvisibleOnlyName` to the totality condition → floor `'Someone'`. Property test in TWO oracles (Gate r3 [P2] — the batch-veto contract is against the RULES, and Dart↔rules diverge on whitespace per V16, so the Dart mirror alone cannot prove it): (a) Dart — for V1–V16 + every full-K input, output passes the NEW `displayNameValidationError == null`; (b) RULES — feed the same outputs through the Task-4 emulator harness as member/activity `actorName` writes and assert they pass the NEW `isValidDisplayName`. Extend the existing sanitizeActorName tests in place.

### Task 4: Firestore rules (RED → GREEN) — net-ZERO new `matches()`

**STEP 0 (Gate r3 [P2] — do this BEFORE building the fold):** the `\x{…}` brace-hex escape has ZERO in-repo precedent (every existing rules escape is 2-hex `\xXX`), and the whole fold depends on Firestore's RE2 binding accepting it. Write a 1-line emulator probe first: a throwaway rule/test with `s.matches('\\x{200b}')` against a ZWSP string. If the binding REJECTS brace-hex, the documented fallback is embedding the raw invisible chars in the rules pattern string (the ONE permitted exception to the escapes-only policy — rules has no `\uXXXX`; isolate the raw-literal line with a loud comment and a hexdump-pinning test).

- `isValidDisplayName` :43 — REPLACE the charset matches with ONE combined charset+floor pattern (RE2-legal, r2 hand-verified equivalent):
  `s.matches('^[^\\x00-\\x1f\\x7f\\x{00ad}\\x{200b}\\x{200e}\\x{200f}\\x{202a}-\\x{202e}\\x{2060}-\\x{2064}\\x{2066}-\\x{2069}\\x{feff}]*[^\\x00-\\x1f\\x7f\\x{00ad}\\x{200b}\\x{200e}\\x{200f}\\x{202a}-\\x{202e}\\x{2060}-\\x{2064}\\x{2066}-\\x{2069}\\x{feff}\\s\\x{200c}\\x{200d}][^\\x00-\\x1f\\x7f\\x{00ad}\\x{200b}\\x{200e}\\x{200f}\\x{202a}-\\x{202e}\\x{2060}-\\x{2064}\\x{2066}-\\x{2069}\\x{feff}]*$')`
- `displayNameMapValuesAreValid`: :56 join('') charset extended with the same `K` escapes; :58 per-value class `[^\n ]` → `[^\\n \\x{200c}\\x{200d}]`.
- Comment cites #1216, joiner rationale, `validFreeText` deliberately unchanged.
- RED via emulator (`cd functions && npm run test:emulator -- <file> -t "<group>"` — NEVER bare jest), extend the covering rules suite with V1–V16 on a member-doc write + an event `participantNames` map write; then the FULL rules suite — a previously-green heavy event/expense-update test failing "maximum of 1000 expressions" = budget regression (#723): fold further, don't chase test logic. **No deploy.**

### Task 5: Functions NAME validators (RED → GREEN)

EXACTLY TWO files: `shared/displayName.ts:8` and `joinGroupByInviteCode.ts:70` — extend each pattern with `K` (escapes, keep each site's flag style) + the floor (`/[^\s‌‍]/u.test(trimmed)`). Add a transitive-coverage test: `recordSettlement` with `payerName: 'Ali‮'` → `invalid-argument`; and a note-path pin: settlement note containing `​` still ACCEPTED (`nullableFreeText` untouched). V-vectors + full-K iteration in the covering suites.

### Task 6: Full check + PR

`flutter analyze`; `flutter test` (full — the validator is widely used); `cd functions && npm run test:emulator` (full); ONE PR: summary, per-layer RED outputs, **`Refs #1216` in PR body AND commit message (never `Closes` — partial delivery)**, `Spec: docs/plans/2026-07-13-1216a-name-format-chars-validation.md` (ship the spec in the branch), the ⚠️ deferred-deploy line. No auto-merge — lead runs /automerge.

## Acceptance

- [ ] V1–V15 verdicts identical across Dart, rules emulator, both TS name validators; V16 pinned with the ACTUAL emulator verdict recorded; full-`K` iteration green in Dart + TS.
- [ ] `sanitizeActorName` totality vs the NEW rules (property test over V1–V16 + K).
- [ ] Free text byte-identical everywhere (client + rules + both TS note validators; ZWSP-note ACCEPT pins on client AND recordSettlement).
- [ ] Full rules suite green; no 1000-expression regressions; matches() count per name unchanged.
- [ ] Nothing deployed; PR body carries the deferred-deploy flag; `Refs #1216` (not Closes) in body AND commit.
