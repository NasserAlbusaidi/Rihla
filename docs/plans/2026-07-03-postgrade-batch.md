# Post-grade batch — the 8 signed-off decisions (#840/#841)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> **EXECUTION HOLD:** specs authored 2026-07-03; user compacts before build. Resume order: (1) `/run-the-gate` on §PR-7, (2) builders per the sequencing below, (3) `/automerge` each, (4) ask about the re-grade. AR-type (§PR-8) additionally blocked on mockup sign-off.

**Goal:** Ship the eight user-approved post-re-grade items: the six bug-class sweep fixes, the bell glyph+badge, the add-people link CTA, the QR strip, and the History-row deep-links; AR-type tokens follow mockup sign-off.

**Architecture:** Seven PRs, ARB-collision-sequenced. Every file:line below comes from five fresh mappers against `753c7fc7` (workflow `wf_9419767b-53a`; full maps in its journal). All display-only; the single Gate-category section is §PR-7 (nav targets built from client-forgeable metadata).

**ARB sequencing (the only inter-PR dependency):** PR-1 (ARB value edits) → PR-6 (ARB key removals) → PR-3 (ARB key additions), each rebased+`flutter gen-l10n` after the previous merges (generated-file conflicts otherwise). PR-2, PR-4, PR-5, PR-7 touch no ARB → fully parallel. Every PR: RED-first where testable, `Refs #840` or `Refs #841` in the COMMIT body (partial deliveries of cluster issues — never `Closes`), theme-purity locally, `/automerge`.

---

## PR-1 — copy sweep (sweep items 2, 4, 5) — ARB-only + one doc comment. EXEMPT-expected.

1. **Settle scope-note recopy** (`settleScopeNoteGroup`, en:1241 / ar:454; rendered by `settle_scope_note.dart:43-46` via `settle_up_page_body.dart:321`). Current claim "won't even out each event's own ledger" is FALSE for the common path: #752 `_recordDecomposedSettlement` (`group_settle_up_screen.dart:744-870`) writes per-event settlements whenever both parties ∈ `group.memberIds` and ≥1 event slice attributes; only the cross-event residual stays group-level ("Across events", `groupSettleUpAcrossEventsLabel`); the single-group-write fallback fires only for departed-party/zero-attribution transfers (:770-788). New copy must be true for BOTH paths — e.g. EN: "Recording here settles across the whole group — Rihla spreads it over each event's ledger where it can; anything left over is tracked at group level." (+AR). Also update the STALE pre-#752 doc comment at `settle_scope_note.dart:12-25`. Tests pin via l10n getters only (`settle_scope_note_test.dart:31-91`) → recopy stays green; RED-first not applicable to pure recopy — instead paste before/after strings in the PR body and cite the #752 write path as evidence.
2. **Join-hint softening** (`groupJoinHintBody`, en:1970 / ar:780; `_JoinHintCard`, `join_group_screen.dart:632-669`). A has-shadows signal is NOT available at hint-render time (only `listUnclaimedShadows` at submit, which rejects anon callers — `listUnclaimedShadows.ts:41-46`), so conditional copy is infeasible: soften unconditionally — plain join stays "instant"; drop/qualify "no approval needed" (the claim-a-shadow branch is creator-approved). No test pins these strings.
3. **AR `ledgerSplitWays` recopy** (ar:240, ICU =1/=2/few/many/other; sole surface `ledger_day_card.dart:249-250`). Replace the "طرق" (roads) phrasing with person-based phrasing (e.g. "مقسّم بين ٣ أشخاص" family across all plural branches; =2 uses the dual). AR-ONLY — EN (en:698) untouched, so `ledger_split_ways_test.dart` + `ledger_screen_overflow_test.dart:327` stay green; `generated_l10n_surface_test.dart:155-159` only asserts non-emptiness. NOTE: sibling keys `editorSplitSummary`/`editorSplitEvenly` carry the same wording but are currently UNUSED by any widget — fix their AR too (cheap, same commit) or leave; do not wire them anywhere.

Run `flutter gen-l10n`, commit generated. Commit: `fix(l10n): honest settle scope note, softened join hint, AR split phrasing` + body `Refs #840` / `Refs #841` (items 2,4 → #840; item 5 → #841).

## PR-2 — widget sweep (sweep items 1, 3) — display-only. EXEMPT-expected.

1. **Dead chevron removal**: `expense_success_dialog.dart:233-237` — delete the `DirectionalIcon(Iconsax.arrow_right_3…)` (and the now-unused `directional_icon.dart` import at :8; the preceding `const Spacer()` at :232 may stay or go with the Row's balance). No InkWell exists anywhere in the card — removal, not wiring, per the decision. Only test pumping the dialog is an overflow test asserting nothing about the chevron (`expense_success_dialog_test.dart:35-52`) — RED-first n/a; add one assertion `find.byType(DirectionalIcon)` findsNothing in that dialog test (write it first, watch it fail while the chevron exists → genuine RED).
2. **RTL transfer arrow**: `group_settlement_tile.dart:151-158` — replace `Positioned(right:0)` with `PositionedDirectional(end:0)` (precedent: `custom_split_sheet_itemized.dart:544`) and the bare `Icon(Iconsax.arrow_right_1)` with `DirectionalIcon` (`lib/shared/widgets/directional_icon.dart`). Replace the hardcoded `' -> '` TextSpan at :188 with a direction-safe separator (`' ← '`/`' → '` via DirectionalIcon is for icons — for the TextSpan use `'‎ → '`? NO — simplest: an RTL-safe glyph choice: use `' ⟵ '`-free approach — replace the ASCII with the proper arrow character wrapped so RTL renders correctly, or restructure to avoid an inline arrow; builder verifies visually in the RTL test). RED-first: update `group_settlement_tile_test.dart:101` (pins the literal `'Sam -> Bob'`) to the new rendering + add an RTL-directionality assertion; note `icon_rtl_guard_test.dart:59-61` currently EXCLUDES `arrow_right_1` — REMOVE that exclusion in this PR so the guard prevents regression.

Commit: `fix(ui): remove dead category chevron; RTL-correct settlement transfer arrow` + `Refs #840`.

## PR-3 — EN-leak l10n (sweep item 6) — auth-surface strings. Classify honestly at /automerge (auth-adjacent → expect GATE review).

Surfaces (all display-only; NO auth logic changes):
1. `auth_email_link_bootstrap_provider.dart` — 5 hardcoded snacks (:113-117, :176-182, :188, :193, :222) + the 7-string EN `humanizeAuthErrorCode` map it calls (:214). Localize via the #843 precedent (`recovery_outcome_notice_provider.dart:43-58`: `appMessengerKey.currentContext → AppLocalizations.of(ctx)`, EN-literal fallback). New ARB keys EN+AR for each distinct string; `humanizeAuthErrorCode` becomes localized with the EN map as fallback. TRAP: `recovery_outcome_notice_test.dart:333-343` pins the humanizer's EN mapping — update those assertions to the localized contract, don't patch around.
2. **Set-name validator**: swap the raw-EN `validateDisplayName` (`name_validators.dart:67-78`) for the EXISTING `validateDisplayNameLocalized` at the two leak sites — `edit_name_bottom_sheet.dart:53` and `settings_provider.dart:107` (ArgumentError backstop: keep EN there if no context — it's a programmer backstop, decide in-diff). The localized twins (`nameValidation*`, en:1441-1451 / ar:502-505) carry IDENTICAL EN copy → EN-pinning tests survive.

RED-first: AR-locale widget test on the edit-name sheet validator message + one bootstrap-snack localization test (mirror #843's AR widget test). `flutter gen-l10n`, commit generated. Commit: `fix(l10n): localize email-bootstrap snacks and set-name validation (#841 leaks)` + `Refs #841`.

## PR-4 — bell glyph + badge. EXEMPT-expected (home display; no ARB).

Per the map: bell = `_IconCircle(key: HomeKeys.activityBell, icon: Iconsax.notification)` at `home_screen.dart:526-540`; `_IconCircle` (:617-639) takes `IconData` — no badge slot.
1. **Glyph → `Iconsax.activity`** (matches the History tab's own inactive glyph, `bottom_nav_shell.dart:174` — strongest destination scent; `Iconsax.clock` noted as the rejected #807-precedent alternative). Iconsax 0.0.8 has NO `history` glyph. Leave the two genuine-notification `Iconsax.notification` sites alone (`notification_rationale_sheet.dart:94`, `profile_screen.dart:982`).
2. **Badge inside `_IconCircle`**: new optional `bool showBadge = false` param wrapping the inner `Icon` in `Badge(isLabelVisible: …, smallSize: 8, backgroundColor: context.colors.primary)` — mirror `bottom_nav_shell.dart:168-178`. External wrap is REJECTED (dot lands on the 40×40 box corner, not the glyph). `_TopBar` is already a ConsumerWidget → `ref.watch(activityUnreadProvider)`.
3. **New key `HomeKeys.bellUnreadBadge`** — NEVER reuse `activityUnreadBadge`: HomeScreen contains BottomNavShell (`home_screen.dart:57`), duplicate keys blow up `tester.widget<Badge>` reads (`bell_tab_select_test.dart:197`).
4. **semanticLabel**: `_IconCircle` gains optional `String? semanticLabel` wired into its existing `Semantics(button:true)` (:626-627); bell passes `context.l10n.homeBottomNavActivity` ("History"/"السجل") — zero ARB churn.
5. Clear-path: nothing new — the bell already routes `_selectTab(1)` → `markSeenNow` (`bottom_nav_shell.dart:52-55`).

RED-first: (a) bell badge visible with unread + hidden with empty feed (new key); (b) extend "bell tap clears the unread dot" to read the BELL badge (no back-to-Groups dance needed — the bell has no selectedIcon duality); (c) glyph pin via `find.descendant(of: find.byKey(HomeKeys.activityBell), matching: find.byIcon(Iconsax.activity))` — note `ledger_activity_entry_test.dart:129` pins that icon on LedgerScreen only, no collision. Commit: `fix(home): history glyph + unread badge on the top-bar bell` + `Refs #840`.

## PR-5 — add-people link CTA. Auth-adjacent; classify honestly at /automerge.

Per the map: the disabled hint is a keyless footer `Text` INSIDE `ShadowMemberChipsField` (`shadow_member_chips_field.dart:143-154`); enablement `online && durable`, hint keyed on durability only (`create_group_screen.dart:397-405`).
1. **Screen-level CTA, not a widget-API change**: in `create_group_screen.dart`, directly below the chips field, render a `TextButton` labeled `context.l10n.profileAccountLinkGoogle` ("Link Google account", en:481/ar:142 — zero ARB churn), shown iff `!isDurable` (mirror the hint's durability-only condition; offline taps get the sheet's own `authErrorOffline` handling — accepted, matches hint behavior). New key `GroupKeys.createLinkAccountCta`.
2. **Handler**: `showDurableCredentialSheet(context)` — BARE, no intent, matching all 3 existing callers (`profile_screen.dart:549,:1189`, `account_backup_nudge.dart:116`). On success `userChanges()` fires → `isDurableUserProvider` flips live → field enables in place, CTA self-hides. **Deliberate scope decisions (name in PR body):** (a) NO `PendingGateIntent` — a conflict-switch taken mid-create loses the typed form (rare; double-gated inside the sheet on `outgoingShellProvablyEmpty` — render :208-219 + tap-time :143); passing an intent would re-scope open issue #825. (b) The sibling in-group surface (`group_members_section.dart:77-94`, `membersCreatorOnlyNote`) is OUT — follow-up if wanted.
3. **Do NOT touch**: the Create-button path (`durable_gate_wiring_test.dart:103` pins anon-Create-with-no-sheet), the boot-frame flicker (accepted, `2026-07-03-remove-anon-create-gate.md:106-111`), any swap gating (safety stays inside the sheet; CTA visibility is not a safety boundary).

RED-first: anon → CTA visible below the disabled field; tap → sheet opens (existing sheet test keys `durableGate.*`); durable harness default (`create_group_shadow_members_test.dart:97-101`) → CTA absent; the existing exact-string hint assertions (:180-186) stay green (hint text untouched). Commit: `feat(groups): link-account CTA under the disabled add-people field` + `Refs #840`.

## PR-6 — QR strip. EXEMPT-expected (display removal).

Per the map there is NO honest per-user payload (handle is a render-time vanity slug — never persisted, never unique, resolvable nowhere; no /u/ route in router, Hosting, or callables; the sheet's own comment admits the 404). **Remove the QR affordance entirely; keep the @handle text chip** (pinned by `profile_screen_test.dart:316,:339` — #163).
- Remove: the QR `_IdentityChip` + its `SizedBox(width: space8)` spacer (`profile_screen.dart:448-472`; chip at :452-458, hardcoded 'QR' label — no l10n), `lib/features/settings/widgets/profile_qr_sheet.dart` (whole file), `ProfileKeys.qrCard` (`profile_keys.dart:27`), l10n keys `qrSheetTitle`/`qrSemanticsLabel`/`qrCopyHandle`/`qrHandleCopied` from BOTH ARBs + regenerate (dead getters fail analyze), and `test/features/settings/profile_qr_sheet_test.dart` wholesale (CLAUDE.md: delete obsolete assertions, don't patch).
- Keep: `qr_flutter` in pubspec (the group invite sheet `qr_invite_sheet.dart` uses it — the honest join-link QR), `profileSnackHandleCopied` (the chip's alias key), the copy chip.
- RED-first n/a for pure removal: instead assert-first — add `find.byKey(ProfileKeys.qrCard)` → wait, the key is being deleted; the removal test is: profile renders with NO 'QR' chip (`find.text('QR')` findsNothing) — write it first (fails while chip exists), then remove.

Commit: `fix(profile): remove the QR sheet — @handle has no lookup to scan to` + `Refs #840`. Note the empty-slug edge (Arabic-only name → bare '@' chip) as a known nit in the PR body (out of scope).

## PR-7 — History-row deep-links (GATE — run `/run-the-gate` on this section before code)

Current: ONE shared `_ActivityRow` onTap pushes `/group/${entry.groupId}` for all 8 types (`cross_group_activity_screen.dart:678-679`). All target routes ALREADY EXIST — **no `app_router.dart` change** (any router edit would be its own Gate category; not needed).

**Per-type target table** (params from metadata are CLIENT-FORGEABLE — see guards):

| type | target route | params | fallback |
|---|---|---|---|
| expense_added, expense_edited | `/group/:gid/event/:eid/ledger` | `eventId` from metadata | group detail |
| expense_deleted | `/group/:gid/event/:eid/activity` (the audit feed is the only place a deleted expense is visible) | `eventId` | group detail |
| event_created | `/group/:gid/event/:eid` (hub) | `eventId` | group detail |
| event_deleted | group detail (unchanged — target is gone; a _NotFoundState dead-end helps nobody) | — | — |
| group_settlement | `/group/:gid/settle-up` (metadata has NO eventId even for #752 decomposed settle-ups — group settle-up is the only honest target; do NOT pass `?memberId=` in v1) | — | — |
| member_joined, member_left, unknown/default | group detail (unchanged) | — | — |

**Non-negotiable guards (the reason this is Gated):**
1. `entry.groupId` ONLY from fetch context (`cross_group_activity_pager.dart:102-110`) — NEVER `metadata.groupId` (client-forgeable on member_joined; a forged groupId cross-group-navigates; a forged eventId under the true groupId merely lands on `_NotFoundState`, which is safe).
2. Every metadata param read: `value is String && value.isNotEmpty` — the #814 rules floor types 11 named keys but leaves `eventId`/`expenseId` OPAQUE, and legacy pre-#814 docs have no floor. Copy the `_metadataString` pattern (`activity_display.dart:32-35`, file-private — export it or add a sibling helper). Guard failure → group-detail push.
3. Resolution LAZY inside `onTap` — never in build and never shared with `activityMatchesQuery` (:190-218 runs over every loaded entry; one throwing row ErrorWidgets the whole tab — the #808 P1 class).
4. `#666`: no PopScope; keep the existing `GoRouter.of(context).push(<path string>)` idiom (proven from both tab and routed contexts). Targets are nested → back pops correctly (#243).
5. Targets' own guards handle stale links (verified: edit/ledger/hub/activity all render not-found/read-only states for deleted/closed/missing).
6. Out of scope, named: per-group `GroupActivityScreen` rows stay inert (current design); home RECENTLY rows (`home_screen.dart:237-238`) keep pushing group detail.

RED-first tests (follow the `*_navigation_test.dart` convention): per-type route assertions (harness fake router currently defines only /home, /activity, /group/:id — `cross_group_activity_screen_test.dart:137-158` — add the target routes); REWRITE the pinned uniform-push test (:605); forged-metadata table: `eventId` as int/bool/map → group detail + NO ErrorWidget; absent eventId → group detail. Commit: `feat(activity): History rows deep-link to what they describe (#840)` + `Refs #840` + `Spec:` line → this doc §PR-7.

## PR-8 — AR type tokens (BLOCKED on mockup sign-off)

Mockup: `docs/design/mockups/841-arabic-type.html` (vault backup exists). On sign-off of Option B: new `AppTypography.caption()` (Latin = current mono recipe; AR = sans-fallback w700/11px/spacing 0/no uppercase), `display()` locale guard (AR → upright w500), `mono()` re-documented numerals-only + migrate its ~dozen text-caption call sites. Spec to be written AFTER sign-off (own doc, DESIGN.md update included).

---

**Verification-principles record:** all file:line claims above are mapper-verified against `753c7fc7` (five mappers, `wf_9419767b-53a`); load-bearing ones for the Gate section (row onTap :678-679, #814 floor coverage, `_metadataString` privacy, pager enrich source) to be re-verified by the Gate reviewer from zero context. No money math, no schema, no rules, no server anywhere in PR-1..7. INBOUND-only surfaces throughout; the one identity-sensitive surface (PR-7 params) is guarded per the table above.
