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
| Cloud Functions (3 callables) | `docs/CLOUD-FUNCTIONS.md` |
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

## The Gate — fresh-context review before implementation

A plan/spec authored in-session ships its author's blind spots into the implementation. The in-session checklist below does not catch this on its own: every worked example in `docs/SPEC-VERIFICATION.md` is a logged case where the embedded check missed it and an independent fresh-context reviewer caught it. The checklist is the reviewer's rubric, not a substitute for the reviewer.

**Mandatory before writing code — NOT only for hand-offs — when the change touches ANY of:**

- `BalanceCalculator` / money math / `MoneySerializer`
- `security/firestore.rules` or Cloud Functions auth/validation
- routing (`app_router.dart`, route tree, deep links, back guards)
- a data-shape / schema / field-name change with both a read-path and a write-path

→ Run `/codex` (or a fresh-context Claude instance with zero session history) against the spec **before implementation**. Apply findings, re-run, stop when the verdict has no [P1]s. ~2 rounds typical; 3 means the spec was over-scoped to start. This gate is unconditional for the categories above. "It's not being handed off" is **not** an exemption — the disasters happen in-session too. Convergence pressure (sycophancy, momentum, prior approval) is exactly what this interrupts.

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

`main()` inside `SentryFlutter.init`: Firebase → optional emulator → SharedPreferences → `runApp`. `_AuthGate` ensures anon session (retries on `internal-error` for corrupted restored sessions) before `SafarApp`. `sharedPreferencesProvider` throws by default; overridden in `ProviderScope.overrides` and in tests.

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

`decimal` package, never `double`. Default OMR (3dp); also USD/EUR/GBP/SAR/AED/QAR. `BalanceCalculator` lives in `lib/features/ledger/providers/expense_provider.dart` (**not** a separate file — people hunt for a `balance_calculator.dart` that doesn't exist). Scopes: global/subGroup(legacy)/personal/custom. Splits: equally/shares/exact/percent. **Rounding remainder → alphabetically-last recipient** so `sum(shares)==amount` — don't move without updating `balance_calculations_test.dart`. Settlement opt: greedy min-transactions. `MoneySerializer` converts `Decimal`↔integer subunits **only at the Firestore boundary**; inside the app stay in `Decimal`. Scale: OMR/KWD/BHD=1000, USD/EUR/GBP/SAR/AED/QAR=100, **JPY=1** (easy to forget).

## Key Invariants

- Soft delete: expenses `isDeleted`+`deletedAt`; settlements **append-only** (B3 — corrections = new offsetting row); events/groups soft-delete too.
- Ownership (B1): `createdBy` immutable on expenses/settlements; only creator edits/soft-deletes own rows. Client + `firestore.rules`.
- Name-based members: creator adds names + picks own; joiner enters invite code + picks unclaimed name. Lives on `groups/{gid}/members/{uid}`, mirrored from `settingsProvider.deviceName`.
- Event modules: only `ledger: true` after Phase 39; model silently ignores legacy keys for compat.
- Group join: via `joinGroupByInviteCode` Function — atomic, validated, rate-limited 5/hr/UID, idempotent.
- Account recovery (v1.2): optional email-link; `AuthRecoveryService` orchestrates; linked email permanent. **Cross-UID isolation of the Firestore on-device cache is an OPEN item (#45 / PR 2) — the SQLite-wipe `UidChangeListener` was removed with the cache in #50; do not assume cross-UID leak protection exists until #45 lands.**
- Account deletion: Profile→Account→Delete → server cascade (auth, Firestore, FCM); Sentry redacts email PII.
- Onboarding: 3-page, gated by `onboardingComplete` in `AppSettings`; router hard-redirects all non-onboarding routes until complete.
- Auth: anon sign-in, no login screen. Deep links: `rihla.app/join/<code>` pre-fills code; recovery via App/Universal Links. Legal: `rihla.app/privacy|terms|delete-data`.
- Routing landmines: GoRouter 13 declarative; direct-entry screens (deep links, recovery) must guard back — `if (!context.canPop()) go('/home')`; covered by `test/features/.../direct_entry_*`. `EventCommandCenter` (`/group/:gid/event/:eid`) is dead-but-kept (V5R-dots experiment) — UI jumps straight to `/event/:eid/ledger`. `BottomNavShell` stacks 3 tabs via `AnimatedOpacity`+`IgnorePointer`, **not** GoRouter-driven. Full tree: `app_router.dart`.

## Common Gotchas

- `prefer_const_constructors` fails CI — mark const-eligible literals `const`.
- Removing a UI element: grep tests for the removed label/key and delete obsolete assertions, don't patch them.
- `AuthEmailLinkBootstrap` double-fire on cold start — regression-test `test/features/auth/` if you touch auth deep-link/bootstrap.
- Horizontal strips (`LedgerRosterStrip`, category) need `SingleChildScrollView`/`Flexible` — `ledger_screen_overflow_test.dart` catches RenderFlex.
- Currency rounding drift = remainder logic moved; contract is alphabetically-last.
- Test fixtures lag label changes: `'SPENDING'` not `'TREASURY'`, `'Ledger'` not `'Audit Log'`.
- App Check: `RIHLA_APP_CHECK_READY` repo var gates release CI; `RIHLA_CONFIRM_APP_CHECK_READY=yes` gates the local script. Both required.
- Java split: Android = 17, Firebase emulator/Functions = 21. Goldens are macOS-only — don't regenerate on Linux.

## Testing

`test/unit/` pure logic (FakeFirebaseFirestore), `test/features/<f>/` widget, `test/integration/` happy/offline/auth/money round-trips, `test/goldens/` dark baselines (macOS, CI-excluded), `test/helpers/` utils — use the existing boot helper (`sharedPreferencesProvider` throws by default and must be overridden in every app-booting test). CI enforces **80%** raw line coverage (`release_android.yml`, `readiness_check.yml`); local ~82%.

## Database

Firestore is source of truth; offline reads/writes are served by the **Firestore SDK's own offline persistence** (`persistenceEnabled`, unlimited cache, set in `firebase_config.dart`). The hand-rolled SQLite cache (`safar_cache.db`, `LocalDatabase`, `lib/core/services/cache/`) was **removed in #50 — do not reintroduce a local cache or `sqflite`; extend `FirestoreRepository`.** Paths + security model: `security/firestore.rules` + `docs/ARCHITECTURE.md`. Functions: `functions/src/` (TS, Node 20), Jest under Java 21 + emulator.

## CI/CD & Docs

`release_android.yml` (manual / `v*` tag): analyze + test + obfuscated AAB + Play alpha; secrets `KEYSTORE_BASE64 KEY_PROPERTIES CONFIG_JSON GOOGLE_PLAY_JSON_KEY`; gated on `RIHLA_BACKEND_RELEASE_READY` + `RIHLA_APP_CHECK_READY`. `readiness_check.yml` (main/PR): analyze + color lint + 80% tests, **no deploy**. Play listing decoupled: `bundle exec fastlane android icon|listing` (needs Homebrew Ruby 3.x). No iOS CI. Toolchain: Flutter ^3.10.1, AGP 8.9.1, Kotlin 2.1.0. Docs under `docs/`: `GETTING-STARTED DEVELOPMENT CONFIGURATION ARCHITECTURE PRODUCT TESTING PRODUCTION-READINESS REAL-DEVICE-QA`; design specs `docs/design/`; plans/research `docs/plans/ docs/research/`.
