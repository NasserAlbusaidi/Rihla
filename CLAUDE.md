# CLAUDE.md

Rihla — Flutter group expense splitter. Solo-dev. **The Operating Contract is the top section and overrides convenience. Everything under `# REFERENCE` is lookup only.** Read the contract every session.

## Quick Nav

| Doing… | Open |
|---|---|
| Anything multi-file, money, routing, schema | **Operating Contract** (below) — non-negotiable |
| Screen / nav flow | `lib/core/router/app_router.dart` + Do/Don't |
| Money math | `BalanceCalculator` in `lib/features/ledger/providers/expense_provider.dart` |
| Firestore stream | `lib/core/services/firestore_repository.dart` |
| New screen design | `docs/design/` + tokens in `lib/core/theme/tokens/` |
| Tests | `test/helpers/`, `flutter_test_config.dart` |
| Release | `docs/PRODUCTION-READINESS.md` + `tool/check_release_readiness.sh` |
| Play Store listing | `fastlane/README.md` |
| Deeper system picture | `docs/ARCHITECTURE.md` |
| Spec-verification worked examples | `docs/SPEC-VERIFICATION.md` |
| Localization (ARB / RTL / `context.l10n`) | `docs/LOCALIZATION.md` + `docs/HOWTO-TRANSLATE.md` |
| Cloud Functions (4 callables + 3 triggers) | `docs/CLOUD-FUNCTIONS.md` |
| Firestore security rules (by collection) | `docs/SECURITY-RULES.md` |
| Anon auth + email-link recovery rationale | `docs/ACCOUNT-RECOVERY.md` |
| First feature walkthrough (newcomers) | `docs/TUTORIAL-FIRST-FEATURE.md` |
| Shared UI building blocks (`lib/shared/`) | `docs/SHARED-WIDGETS.md` |

Also always in context: `MEMORY.md`. Product framing: `docs/PRODUCT.md`.

---

# OPERATING CONTRACT

If this conflicts with anything under REFERENCE, this wins.

## Response style — with one exception

Terse, action-first, no trailing summaries, don't re-explain what the code already shows. **Exception: plan/spec verification output is not "over-explaining."** When verifying (see The Gate), state what you checked, the exact command you ran, and what you found — explicitly, out loud. Terseness never suppresses verification reporting. These two rules do not compete; this carve-out is the tiebreak.

## Memory — one rule, no ambiguity

`MEMORY.md` / auto-memory exists so you don't re-ask the user things already settled (preferences, prior decisions). It is **never a citation.** Any claim sourced from memory, CLAUDE.md, or a code comment that touches a write path, money math, routing, or schema must be re-confirmed against code (`grep`/`Read`) before it enters a plan or spec. Memory orients; code decides. Do not resolve this toward "trust memory" because re-checking is friction — re-checking is the job.

**Same rule for agent/doc output — scoped to merge/done/release-state claims.** Any "PR merged", commit SHA, "QA passed", or deploy/release-gate claim — from memory, a delegated agent, an issue comment, or a doc — gets one mechanical check before you repeat or act on it: `git cat-file -t <sha>` / `gh pr view <n> --json state,mergeCommitOid`. Agents fabricate completed work that passes plausibility (hallucinated merge SHAs `4f3e8d9`/`51c5ce4` that were never git objects; an invented QA run with a fake anon UID written into a release-gate doc) — this is the project's signature failure mode. Scope the check to merge/done/release-state — **not** every agent-added identifier; the one-sentence-diff path stays exempt.

**Destructive batch sweeps get an adversarial refute, not a spot-check.** When a fan-out/triage verdict drives an *irreversible* action across many items — closing issues, deleting branches, dropping stashes — re-checking only the ones you happen to act on is not enough: it let a half-done #223 (sign-validation shipped, sum-validation never written) reach a `close`. Run every `already-done`/`drop`/`safe-to-delete` verdict through a **fresh skeptic prompted to refute it** (find the unmerged commit / the unmet acceptance box) before acting; only verdicts that survive get executed. `.claude/workflows/verified-sweep.js` encodes this (investigate → refute → act); reach for it on any multi-item close/delete sweep.

## The Gate — fresh-context review before implementation

A plan/spec authored in-session ships its author's blind spots into the implementation. The in-session checklist below does not catch this on its own: every worked example in `docs/SPEC-VERIFICATION.md` is a logged case where the embedded check missed it and an independent fresh-context reviewer caught it. The checklist is the reviewer's rubric, not a substitute for the reviewer.

**Mandatory before writing code — NOT only for hand-offs — when the change touches ANY of:**

- `BalanceCalculator` / money math / `MoneySerializer`
- `security/firestore.rules` or Cloud Functions auth/validation
- routing (`app_router.dart`, route tree, deep links, back guards)
- a data-shape / schema / field-name change with both a read-path and a write-path

→ Run a **fresh-context Opus subagent** (zero session history) against the spec **before implementation** — `/run-the-gate` drives it (spawn `Agent{subagent_type: general-purpose, model: opus}`; never reuse this session's context). Apply findings, re-run with a *new* subagent each round, stop when the verdict has no [P1]s. ~2 rounds typical; 3 means the spec was over-scoped to start. This gate is unconditional for the categories above. "It's not being handed off" is **not** an exemption — the disasters happen in-session too. Convergence pressure (sycophancy, momentum, prior approval) is exactly what this interrupts.

Outside those categories (describable as a one-sentence diff, no money/route/schema/rules surface): skip the gate, just do it.

## Verification principles

Run while writing the spec; report results out loud. Full reasoning + worked examples: `docs/SPEC-VERIFICATION.md`.

1. **Classify every callsite on a shared read/write path** — INBOUND (display only) / OUTBOUND (feeds a write) / BOTH (treat as OUTBOUND). Skipping this is how display-formatted strings get persisted unchanged.
2. **Verify every concrete claim against code, not docs.** Paths, route constants, field names, scripts. Re-run the grep in the moment; an upstream agent's citation is not proof.
3. **Trace one read-path per write-path.** "Who reads this after it changes?" must have a named answer.
4. **Enumerate fields from the type, not memory.** Open the model file; list exhaustively.
5. **Spell out data contracts, don't gesture at them.** Exact map keys, exact callback signatures, exact prop names. "Two different shapes" is an intention, not a spec.
6. **Verify arithmetic decomposition.** `aggregate = sum(slices)` asserts the field decomposes across the slicing — read the field-construction lines, not the algorithm flow. (`netBalance` folds settlements; `totalPaid` does not.)
7. **Adversarial pass on an orthogonal axis.** If the fix is on axis A, the worked example must exercise axis B (settlements / money-flow / scope / time / identity). Same-axis examples only re-prove what you already believed. Distrust your own earlier in-session claims; treat each iteration round as v1.

## Workflow

- Plan before multi-file work; capture it as a doc/task list before touching code.
- Bug fix = failing regression test first (RED) → fix (GREEN) → re-run failing test → full suite. No fix ships without a test that would have caught it.
- `flutter analyze` clean before you call anything done; run the relevant tests after.
- Commits: conventional (`feat(scope):` …); match `git log --oneline -20`.
- PRs: review the whole branch diff (`git diff main...HEAD`), not the last commit.
- In doubt about scope: smaller change + follow-up, don't bundle.
- **Merge hygiene kills ghost-debt at the source.** Every PR body carries `Closes #N` (partial → `Refs #N` + name the unmet boxes, issue stays open re-scoped); the repo auto-deletes head branches on merge (`delete_branch_on_merge`). So merged work never leaves orphaned refs + stale-open issues for a later archaeology sweep — the kind that found 16 dead branches and 2 falsely-open issues in one sitting. `.github/pull_request_template.md` carries the ritual.
- **Surface the fan-out plan before launching a large workflow.** A multi-agent / high-token workflow states its clusters in one line *before* spending, so scope can be redirected before the cost — not narrated after it.
- **No Schrödinger's fix.** A fix is in exactly one state: an open PR, merged, or explicitly deferred to a named milestone. Never the resting state of a `git stash` or an unpushed local branch — that's invisible debt that reads as "almost done" forever. (The hardening fan-out left #104 in `stash@{0}` and 6 branches unpushed; all 9 audit issues sat OPEN, 0 merged.)

---

# REFERENCE

Lookup material. Does not override the contract.

## Project Overview

Rihla ("Journey") — Splitwise-style group expense splitter: persistent groups → events → ledger. Package `safar`, Android `com.safar.safar`, version per `pubspec.yaml`. Backend **Firebase only**: Firestore, Auth, Cloud Functions (Node 20/TS), FCM. No Firebase Storage SDK — protected media via Functions. Firestore offline persistence handles offline reads and queued-write replay (the hand-rolled SQLite read-cache was removed in #50). Anon auth on first launch + optional email-link recovery. Supabase migration is **complete — do not add Supabase keys**.

## Essential Commands

```bash
flutter pub get
flutter run --dart-define-from-file=config.json     # config.json at root required
flutter analyze                                      # must be clean before commit
flutter test                                         # full; or test/unit/ , test/features/ledger/ , one file
flutter build appbundle --release --obfuscate --split-debug-info=./build/app/outputs/symbols --dart-define-from-file=config.json
RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/check_release_readiness.sh   # read-only pre-release audit
```

Config injected via `--dart-define-from-file=config.json`, read with `const String.fromEnvironment`. Keys: `SENTRY_DSN`, optional `USE_FIREBASE_EMULATOR`. Platform config (`google-services.json`, `GoogleService-Info.plist`) gitignored, project `rihla-safar`. `lib/firebase_options.dart` is generated by `flutterfire configure` and committed — don't hand-edit.

## Bootstrap Order

`main()` inside `SentryFlutter.init`: Firebase → optional emulator → SharedPreferences → `runApp`. `_AuthGate` ensures anon session before `SafarApp`. **A restored session whose token won't verify is KEPT, never discarded (#213): `recoverRestoredSessionIfNeeded` must never `signOut`+`signInAnonymously` on a token-check failure — for a no-email anon user that mints a new UID and irreversibly orphans all their data. It only ever returns `false`.** `sharedPreferencesProvider` throws by default; overridden in `ProviderScope.overrides` and in tests.

## Architecture

Feature-first under `lib/features/` (`models/ providers/ screens/ services/ widgets/ keys/`). Active: activity, auth, events, groups, home, ledger, onboarding, profile, settings, + legacy trip compat. **Gear/logistics/vault/memories stripped in Phase 39 — do not reintroduce** (related Functions/StorageGateway are dead code). Shared Firestore access via `FirestoreRepository` base or existing feature services — **no new global repositories**. State: Riverpod 2.x, no codegen (`StreamProvider(.family)` for Firestore/auth, `StateNotifierProvider` for complex state, `FutureProvider` one-shot, `Provider.family` for services). **The Firestore SDK serves offline reads from its own persistence and replays offline writes — do not build a custom local cache or sync queue (the SQLite cache was removed in #50).** Deeper picture: `docs/ARCHITECTURE.md`.

## Do / Don't

**Do:** `context.colors|spacing|shadows` for all styling; `EdgeInsetsDirectional` / `AlignmentDirectional` / `Positioned.directional` for start/end layout; `DirectionalIcon` or an explicit RTL flip for navigation arrows and row chevrons; `RAmount` for money, `RAvatar` for people, shared widgets (`lib/shared/widgets/`) before custom; route params via path/query not `extra`; soft-delete `isDeleted`+`deletedAt` (settlements append-only); validate names with `isValidDisplayName` (1–32, no control chars) kept aligned with `firestore.rules`; mock with `mocktail` + `FakeFirebaseFirestore` + `firebase_auth_mocks`; override `sharedPreferencesProvider` in every app-booting test; await Firebase init before auth-dependent writes.

**Don't:**
- ❌ `Navigator.push` for app nav — use `context.go`/`context.push` (readiness greps for it)
- ❌ `state.extra` for required nav data (readiness greps for it) — deep links must work cold
- ❌ `context.goNamed` — path strings only (readiness greps for `goNamed`)
- ❌ Hardcoded `Color(0xFF…)` outside `lib/core/theme/tokens/` (fails CI)
- ❌ `Alignment.centerLeft` / `EdgeInsets.only(left:)` for user-facing layouts — use directional start/end APIs so Arabic RTL mirrors correctly
- ❌ `double` for money — `Decimal` only
- ❌ Reintroduce Memories/Vault/Gear/Logistics (Phase 39)
- ❌ Supabase config or Storage SDK
- ❌ Custom sync queue (SDK replays offline writes)
- ❌ New global repositories — extend `FirestoreRepository`
- ❌ Hand-edit `lib/firebase_options.dart` — regenerate
- ❌ Hard-delete user-visible records — soft-delete

## Financial Calculations — landmines

`decimal` package, never `double`. Default OMR (3dp); also USD/EUR/GBP/SAR/AED/QAR. `BalanceCalculator` lives in `lib/features/ledger/providers/expense_provider.dart` (**not** a separate file — people hunt for a `balance_calculator.dart` that doesn't exist). Scopes: global/subGroup(legacy)/personal/custom. Splits: equally/shares/exact/percent. **Rounding remainder → alphabetically-last recipient** so `sum(shares)==amount` — don't move without updating `balance_calculations_test.dart`. Settlement opt: greedy min-transactions. `MoneySerializer` converts `Decimal`↔integer subunits **only at the Firestore boundary**; inside the app stay in `Decimal`. Scale: OMR/KWD/BHD=1000, USD/EUR/GBP/SAR/AED/QAR=100, **JPY=1** (easy to forget). `_allocateExact` (and every allocator) **must never emit a negative owed** — `firestore.rules` only checks `splitDistribution is map`, not value signs or sum, so a forged/unvalidated write can persist negatives or a tolerance-drift over-allocation; the calculator defends (negative entry → equal-split fallback; in-tolerance residual closes onto the alphabetically-last recipient that can absorb it without going negative). Server-side `splitDistribution` value validation is #192. **`calculateBalances` is a cross-implementation ORACLE: the TS `deleteGroup` server gate (`functions/src/callables/deleteGroup.ts:520-585`, #190) mirrors it byte-for-byte — same per-event universe (`participantIds ∪ (payers+settlement parties \ live)`, NOT split recipients), the same load-bearing "drop owed for any key outside the universe," and (since #223) the same **in-tolerance exact residual close-out** (`deleteGroup.ts` `allocateExact` now mirrors `_allocateExact:507-543`; before #223 it returned the distribution verbatim in-tolerance, so a within-tolerance exact split carried a non-zero residual server-side and the exact `!isZero()` gate at `deleteGroup.ts:692` refused to delete a group the client showed as **settled**). The **lone remaining client-only divergence** is the per-allocator **negative-value→equal-split guard** — the server allocators omit it; harmless because new negatives are rules-blocked at `firestore.rules:492` (#192), only legacy/Admin docs could carry one. `delete_group_balance_parity_test.dart` locks the two together (case 1b pins the in-tolerance residual).** So a key referenced by a split but absent from `participants` is **dropped on purpose** (it's the parity contract, not a bug to "fix" unilaterally) — the realistic conservation gap (a departed explicit-split recipient, #249) must be fixed at the **caller's universe construction on BOTH client and server**, never by changing the calculator's drop semantics, and the per-event drill-down (`_buildPerEventBreakdown`) is intentionally `participantIds`-only (pinned by `group_balance_provider_test.dart`).

## Key Invariants

- Soft delete: expenses `isDeleted`+`deletedAt`; settlements **append-only** (B3 — corrections = new offsetting row); events/groups soft-delete too.
- Ownership (B1): `createdBy` immutable on expenses/settlements; only creator edits/soft-deletes own rows. Client + `firestore.rules`.
- Name-based members: creator adds names + picks own; joiner enters invite code + picks unclaimed name. Lives on `groups/{gid}/members/{uid}`, mirrored from `settingsProvider.deviceName`.
- Event modules: only `ledger: true` after Phase 39; model silently ignores legacy keys for compat.
- Group join: via `joinGroupByInviteCode` Function — atomic, validated, rate-limited 5/hr/UID, idempotent.
- Account recovery (v1.2): optional email-link; `AuthRecoveryService` orchestrates; linked email permanent. **Cross-UID isolation of the Firestore on-device cache is LIVE on `main`: #68 merged 2026-05-30 (`ca85a58`) — cold-start `CacheUidBarrier` + `FirestoreCacheGate` (`lib/core/services/`) + in-session isolation overlay + true restart via the `MainActivity` MethodChannel. Both gates cleared pre-merge: device-QA #67 PASSED and the failure-path re-gate PASSED (fresh-context re-gate R1 FAIL → fix `5c84eba` → R2 PASS). Leak protection now exists on main; the on-device eviction still wants re-confirmation against a fresh release AAB during RD-QA (#40).**
- Account deletion: Profile→Account→Delete → server cascade (auth, Firestore, FCM); Sentry redacts email PII.
- Onboarding: **archived/unreachable** — `OnboardingScreen` is imported nowhere, the router has no `/onboarding` route, and `appRouteRedirect` only maps splash→home (it does **not** gate on `onboardingComplete`). The intent is pinned by `test/unit/app_router_test.dart` ("onboarding route is not part of the shippable route tree"). The `onboardingComplete` flag in `AppSettings` is retained only so legacy installs/the archived screen can read it. Deletion tracked in #56 — don't re-wire onboarding into the route tree without reopening that decision.
- Auth: anon sign-in, no login screen. Deep links + legal pages live on Firebase Hosting: the app generates/parses `rihla-safar.web.app/join/<code>` (also accepts `rihla-safar.firebaseapp.com`); recovery via App/Universal Links. Legal: `rihla-safar.web.app/privacy|terms|delete-data` (the `app_links.dart` constants — verify live). **The bare `rihla.app` domain is dead/parked (Sedo) and was fully dropped per #130 — `web.app` is the sole deep-link host (parser + App Links + iOS entitlements + legal). Never reintroduce a `rihla.app` host or point a user-facing/Play Console URL at it.**
- Routing landmines: GoRouter 13 declarative; **top-level** direct-entry screens (deep links, recovery) must guard back — `if (!context.canPop()) go('/home')`; the live convention is `*_navigation_test.dart` (e.g. `group_detail_navigation_test.dart`), **not** the stale `direct_entry_*` name. **`EventCommandCenter` (`/group/:gid/event/:eid`) is the ACTIVE event-landing hub, NOT dead code, and the UI does NOT jump straight to the ledger** — both the group event-row (`group_detail_screen.dart:214`) and the home journey ticket (`home_screen.dart:544`) push the bare `/group/:gid/event/:eid` path; the user then taps `Ledger →`/`+Add expense` from the hub (`event_command_center.dart:178/201`). (The older "dead-but-kept / jumps straight to `/event/:eid/ledger`" claim was false against code — verified 2026-06-03.) **Back-guard asymmetry is BY DESIGN, not a bug (#243 closed not-reproducible 2026-06-04).** `EventCommandCenter`/`LedgerScreen` do `if canPop() pop()` with no `else go('/home')`; `GroupDetailScreen` has the full `PopScope`→`/home` fallback (lines 52-77). The difference is route depth: `/group/:gid` is **top-level**, so cold-entry makes it the sole stack page (`canPop()==false`) → it genuinely needs the home fallback (pinned by `group_detail_navigation_test.dart:202`). `event/:eid` and `ledger` are **nested sub-routes** — GoRouter materializes the ancestor pages on any nav (cold deep-link / `go` / `push`), so `canPop()` is **always true** and the bare `if canPop() pop()` already pops to the parent (proven green: `event_command_center_test.dart:151` "direct route back button returns to group route"; ledger probed identically). Adding the `else go('/home')` to the nested screens would be dead code, and `PopScope(canPop:false)` would suppress Android predictive-back for no gain — **don't "fix" this asymmetry** unless a screen is promoted to a top-level route. `BottomNavShell` stacks 3 tabs via `AnimatedOpacity`+`IgnorePointer`, **not** GoRouter-driven. Full tree: `app_router.dart`.

## Common Gotchas

- `prefer_const_constructors` fails CI — mark const-eligible literals `const`.
- Removing a UI element: grep tests for the removed label/key and delete obsolete assertions, don't patch them.
- `AuthEmailLinkBootstrap` double-fire on cold start — regression-test `test/features/auth/` if you touch auth deep-link/bootstrap.
- Horizontal strips (`LedgerRosterStrip`, category) need `SingleChildScrollView`/`Flexible` — `ledger_screen_overflow_test.dart` catches RenderFlex.
- Currency rounding drift = remainder logic moved; contract is alphabetically-last.
- **1.0 is OMR-only (#61, decided 2026-06-04).** Every money write path hardcodes `'OMR'` **on purpose** — don't "fix" it by wiring the orphaned `AppSettings.currencyCode` preference (or re-adding a currency picker) to writes. The hard blocker isn't the picker; it's that `paidMap`/`owedMap`/`computeGroupBalances` sum `Decimal`s with **no currency dimension**, so mixed-currency-per-group computes nonsense (10 USD + 10 OMR = "20"). `MoneySerializer`/`BalanceCalculator` are per-expense-currency-correct (#47), but aggregation is not. `currencyCode`/`setCurrency` are **retained infra** for the multi-currency follow-up; the Profile picker was removed (pinned by `profile_screen_test.dart` "currency removed (#61)"). Multi-currency needs an aggregation design (one-currency-per-group or per-currency buckets) + the Gate — it's a post-1.0 feature, not a wiring fix.
- Test fixtures lag label changes: `'SPENDING'` not `'TREASURY'`, `'Ledger'` not `'Audit Log'`.
- App Check: `RIHLA_APP_CHECK_READY` repo var gates release CI; `RIHLA_CONFIRM_APP_CHECK_READY=yes` gates the local script. Both required.
- **Don't add per-IP rate-limiting to Cloud Functions callables (#197).** They run on direct Cloud Run ingress (no external ALB), so `X-Forwarded-For` is fully client-spoofable and `rawRequest.ip`/socket address give Google's internal proxy, not the caller — a per-IP throttle is bypassed by a rotating spoofed header (easier than anon-UID rotation) AND false-positive-locks CGNAT users. Per-actor throttles (`joinAttempts`/`deletionAttempts`/`deleteGroupAttempts`) are friction, not a hard gate; **enforced App Check is the real per-actor control**. A trustworthy client IP needs fronting callables with a Global external ALB + serverless NEG (deferred). Per-code throttling is harmless but marginal (enumeration uses a fresh code each guess).
- Java split: Android = 17, Firebase emulator/Functions = 21. Goldens are macOS-only — don't regenerate on Linux.
- Releasing: **never hand-edit the `pubspec.yaml` version.** `tool/release.sh <patch|minor|major>` bumps it at tag time (`build = current+1`, tag `vX.Y.Z`, no build in tag), commits `chore(release): vX`, and pushes main+tag; CI builds the tagged commit. Leave `main` at the last-released version — a manual pre-bump makes `release.sh minor` emit the wrong semver (1.4.0 instead of 1.3.0). #128 ("bump past +16") closes at tag time, not via a hand commit.
- **Don't flip `docs/PRODUCTION-READINESS.md`'s `- [ ] Firebase production state is not aligned with this branch yet.` to `[x]`** (nor add `- [x] Firebase Functions are deployed in production.`) — `test/unit/release_workflow_gate_test.dart` pins that blocker OPEN until the formal deploy ceremony (`RIHLA_FIREBASE_DEPLOY_APPROVED_SHA` + a recorded `check_firebase_prod_state.sh rihla-safar` PASS vs the release SHA). Verifying prod via the Firebase CLI/REST is **not** the same as satisfying the ceremony; flipping it turns CI red.
- **The deployed-Functions drift check reads its expected set from `tool/list_expected_functions.sh` — NOT an inline `sed`.** `functions/src/index.ts` mixes single-line `export { foo } from …` with multi-line `export { a, b, c } from …` blocks; the old single-line `sed` in `check_firebase_prod_state.sh` silently dropped the multi-line blocks (#53 notifiers, #198 monitors), so the check reported "All expected Functions are deployed" while 5 of 9 were absent — a false PASS, the project's signature failure mode. The extractor is now a shared script (awk, handles both forms) locked by `release_workflow_gate_test.dart` ("expected-functions extractor …"). Don't reintroduce a one-line regex, and add new functions as `export { … } from` re-exports (a bare `export const fn = onCall(…)` in `index.ts` is invisible to both extractors and would escape the deploy check).
- **`fake_cloud_firestore` is clause-order-sensitive: chain `.startAfterDocument(cursor)` BEFORE `.limit()`.** Limit-first returns the wrong slice / throws "document specified wasn't found" against the fake (real Firestore is order-insensitive, so prod is fine either way). Any cursor-pagination test must use cursor-then-limit. `group_activity_service.dart` is limit-first → its pagination is untested past page 1 (#183); the correct pattern is `activity_service.dart` `fetchActivityPageRaw`.
- **`EmptyStateView` schedules a `flutter_animate` entrance ticker**, so any widget test that lands on an empty OR error state (`_ErrorView` wraps `EmptyStateView`) must end with `pumpAndSettle()` (or drain it) or teardown throws "A Timer is still pending." Note this is the OPPOSITE of the `pumpRihlaApp` rule — there you must NOT `pumpAndSettle` because `ConnectivityNotifier`'s Timer never settles.
- **A paginated `ListView.builder`'s `maxScrollExtent` SHRINKS** as off-screen variable-height rows get disposed/estimate-sized, so a single large drag overshoots a stale extent and stalls pagination — use small drag steps / `scrollUntilVisible`. And don't assert by counting on-screen widgets under virtualization; assert a **page-2-only row becomes findable** after scrolling (proves the page loaded, no silent truncation). Activity rows render `actorName` in `Text.rich` → match with `find.textContaining(..., findRichText: true)`, not the raw `logText` (never displayed).
- **Don't `.autoDispose` the ledger/balance providers to "fix" listener leaks (#104).** The always-mounted home dashboard pins them session-long: `BalanceHeroCard → crossGroupBalanceProvider` (all groups) + `activeJourneysProvider` (active groups) → `groupBalancesProvider` → `eventExpensesProvider`/`eventSettlementsProvider` leaves. A provider with a live watcher never autoDisposes, so the annotation is a no-op (empirically confirmed). #104 was instead fixed (#233) by **one-shot home aggregation** — see next.
- **The home dashboard reads event expenses/settlements ONE-SHOT (#104/#233 — `groupBalancesOnceProvider`/`crossGroupBalanceOnceProvider`, computed via the shared pure `computeGroupBalances`), so any NEW event-level expense/settlement write path MUST bump `ledgerRevisionProvider` (in `expense_provider.dart`) after a successful write — or the home balance silently goes stale, which is money-wrong for settle-up.** The four existing bumps are `add_expense_screen` (add), `edit_expense_screen` (update + soft-delete), `settle_up_screen` (event settlement). **Group**-level settlements need NO bump — the once-provider watches the live `groupSettlementsProvider`. Event/group/member **list** changes also refresh live (the once-provider watches those streams); only per-event money *content* needs the bump. Don't "fix" `crossGroupBalanceProvider`/`groupBalancesProvider` (the live variants kept for in-group screens) by pointing home at them — that reopens the O(G×E) listener leak.

## Testing

`test/unit/` pure logic (FakeFirebaseFirestore), `test/features/<f>/` widget, `test/integration/` happy/offline/auth/money round-trips, `test/goldens/` dark baselines (macOS, CI-excluded), `test/helpers/` utils — use the existing boot helper (`sharedPreferencesProvider` throws by default and must be overridden in every app-booting test). CI enforces **80%** raw line coverage (`release_android.yml`, `readiness_check.yml`); local ~82%.

## Database

Firestore is source of truth; offline reads/writes are served by the **Firestore SDK's own offline persistence** (`persistenceEnabled`, unlimited cache, set in `firebase_config.dart`). The hand-rolled SQLite cache (`safar_cache.db`, `LocalDatabase`, `lib/core/services/cache/`) was **removed in #50 — do not reintroduce a local cache or `sqflite`; extend `FirestoreRepository`.** Paths + security model: `security/firestore.rules` + `docs/ARCHITECTURE.md`. Functions: `functions/src/` (TS, Node 20), Jest under Java 21 + emulator.

## CI/CD & Docs

`release_android.yml` (manual / `v*` tag): analyze + test + obfuscated AAB + Play alpha; secrets `KEYSTORE_BASE64 KEY_PROPERTIES CONFIG_JSON GOOGLE_PLAY_JSON_KEY`; gated on `RIHLA_BACKEND_RELEASE_READY` + `RIHLA_APP_CHECK_READY`. `readiness_check.yml` (main/PR): analyze + color lint + 80% tests, **no deploy**. Play listing decoupled: `bundle exec fastlane android icon|listing` (needs Homebrew Ruby 3.x). No iOS CI. Toolchain: Flutter ^3.10.1, AGP 8.9.1, Kotlin 2.1.0. Docs under `docs/`: `GETTING-STARTED DEVELOPMENT CONFIGURATION ARCHITECTURE PRODUCT TESTING PRODUCTION-READINESS REAL-DEVICE-QA`; design specs `docs/design/`; plans/research `docs/plans/ docs/research/`.
