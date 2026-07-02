# Friction audit tranche 2 — activity window, correct label, restore visibility

Source: 2026-07-02 navigation & friction audit (tranche 1 = #801/PR#802).
Three medium findings, all client-only, no schema/rules/Functions/router changes.

## Item 1 — Cross-group activity window (5 → 30)

**Problem.** The Activity tab feed is capped at 5 entries TOTAL across all
groups (`dashboard_providers.dart:71-73` `sublist(0, 5)` over per-group
`.limit(5)` streams — `group_activity_service.dart:39-42` default). The filter
chips then filter that pre-truncated 5-item window: tapping "Settlements" can
show "nothing matches" even though a settlement happened last week.

**Fix (audit's minimal option — widen, don't paginate).**
- `groupActivityProvider` (`group_balance_provider.dart:66-72`): pass
  `limit: 15` to `watchRecentActivity`.
- `crossGroupActivityProvider` (`dashboard_providers.dart`): merged cap 5 → 30.
- Constants split by import direction (Gate P3: `dashboard_providers.dart`
  imports `group_balance_provider.dart` one-way, so a shared constant cannot
  live in the importer): `kCrossGroupActivityPerGroupLimit = 15` sits beside
  `groupActivityProvider` in `group_balance_provider.dart`;
  `kCrossGroupActivityMergedCap = 30` in `dashboard_providers.dart`. Update
  the doc comments that say "5 most recent".
- Home RECENTLY section is unaffected: it slices `entries.take(3)`
  (`home_screen.dart:217`).
- The tab body is already a `ListView.builder` — 30 items scroll fine.

**Why not pagination:** a cross-group cursor merge (N per-group cursors,
k-way merge, fetch-ahead) is real engineering for a feed with no real users
yet; the per-group screen already offers full 50/page history one tap deeper.
Deliberately deferred, mirroring the #422 posture (don't re-propose without
evidence).

**Listener math (the #104 axis).** `crossGroupActivityProvider` is watched by
the always-mounted home (`home_screen.dart:112`) AND the Activity tab, both
through the SAME `groupActivityProvider` family instances — widening the
existing per-group listener from limit(5) to limit(15) adds ZERO new listeners
and no new provider family. Do NOT add a second, differently-limited family
(would double per-group listeners).

**Callsite classification.** `crossGroupActivityProvider` and
`groupActivityProvider` are INBOUND (display-only); grep confirms the only
watchers are `home_screen.dart`, `cross_group_activity_screen.dart`, and
`dashboard_providers.dart`. No write path reads them.

**Test (RED first).** `dashboard_providers_test.dart:113-140` ("limits to 5
entries total") pins the OLD cap and must be REWRITTEN to the new contract
(seed 35 → capped at 30; seed 8 → all 8 emitted), not deleted. Screen test: a
settlement that is 7th-newest overall is findable after tapping the
Settlements chip (fails today — outside the old window).

## Item 2 — Visible "Correct" label on settlement corrections

**Problem.** The only way to fix a mis-recorded payment (settlements are
append-only, B3) is an unlabeled `IconButton(Iconsax.undo)` with tooltip-only
text (`settle_up_page_body.dart:1087-1103`), rendered beside a near-identical
share icon in the last section of the page. Tooltips are invisible on touch.

**Fix.** Replace the bare icon button with a compact labeled action
(`TextButton.icon`: undo glyph + `l10n.settleUpCorrect` — key already exists,
en "Correct" / ar "تصحيح"). Keep `GroupKeys.settleUpCorrectButton` on
`index == 0`, keep the same `onPressed` (`_confirmAndCorrect`), keep the
visibility predicate at :1080-1085 byte-identical (the #752 tagged-settlement
hide is load-bearing — do not touch). The row's name column is `Expanded` +
ellipsis; however NO existing overflow test covers this row (Gate P2 — the
overflow suite lives under `test/features/ledger/` only), and the amount Text
is non-flexible, so a long Arabic name + amount + label could overflow on a
narrow device. Add a narrow-width (320px) pump regression test for the tile
with the correct + share actions visible.

**Tests.** Existing: `settle_up_correction_test.dart`,
`settle_up_logical_row_widget_test.dart`, `group_settle_up_correct_test.dart`
tap by key — unchanged. Add: assert the visible label text renders (not
tooltip-only).

## Item 3 — Restore rows stay visible for anonymous users (tap-gated)

**Problem.** Both profile restore rows render only when
`isAnonymous && groups.isEmpty` (`profile_screen.dart:1106-1108`). Reinstall,
join one group from an invite, then remember your backed-up account → the
restore entry points vanish with no disabled state and no explanation. The
explanatory copy for exactly this (`restoreBlockedHasData`, en:1450) already
exists but is reachable only through `triggerGoogleRestore`'s internal gate.

**Fix — move emptiness from VISIBILITY to TAP, never touch the swap gate.**
- `showRestore` becomes `isAnonymous` alone.
- Google row: `onTap` unchanged — `triggerGoogleRestore`
  (`google_restore_action.dart:27-36`) already runs
  `outgoingShellProvablyEmpty` and snacks `restoreBlockedHasData` when the
  shell isn't provably empty. No change to that function.
- Email row: `onTap` changes from bare `context.push('/recover')` to a gated
  helper. Exact contract (Gate P2 — mirrors `google_restore_action.dart:27-31`;
  the gate takes THUNKS and a `Duration`, and the post-await code needs a
  `context.mounted` guard or `use_build_context_synchronously` fails analyze):

  ```dart
  Future<void> _recoverWithEmail(BuildContext context, WidgetRef ref) async {
    final shellEmpty = await outgoingShellProvablyEmpty(
      readUser: () => ref.read(firebaseUserProvider.future),
      readGroups: () => ref.read(userGroupsProvider.future),
      timeout: ref.read(shellEmptinessGateTimeoutProvider),
    );
    if (!context.mounted) return;
    if (!shellEmpty) {
      // snack restoreBlockedHasData (no per-call `behavior:` — themed floating)
      return;
    }
    context.push('/recover');
  }
  ```

  Without this, a data-holding user reaches the email screen, sends a link,
  and is only blocked at link-open (#647's swap gate at
  `google_restore_action.dart:19` for the Google twin) — a downstream
  dead-end instead of an upfront answer. This check is ADVISORY; the
  authoritative gate still runs at the swap.

**Safety invariants (the #647/#648/#661 class) — unchanged by design:**
1. `outgoingShellProvablyEmpty` (`shell_emptiness_gate.dart`) is NOT modified.
2. Every swap entry point keeps its own gate AT THE SWAP: email-link bootstrap
   (#647), `triggerGoogleRestore` (#648), durable-sheet conflict-switch
   (#661). This change only ADDS one earlier, advisory check on the email
   row's navigation; the authoritative gate still runs at the swap.
3. CTA visibility was never a safety boundary (per the audit and #648's own
   comment: the visibility read FALSE-EMPTIES on the cold-start race). This
   change stops pretending it is one.

**Adversarial pass (orthogonal axes).**
- *Race axis:* cold start, `userGroupsProvider` false-empties → OLD code hid
  the rows (visibility read `valueOrNull`); NEW code shows them (isAnonymous
  only) and a tap awaits the user future FIRST inside the gate — resolves
  correctly instead of guessing. Strictly better.
- *Identity axis:* durable (non-anon) user → rows hidden, unchanged
  (`isAnonymous` retained).
- *Fail-safe axis:* gate timeout/error → blocked + snack (same direction as
  today's hidden row; message slightly overclaims the cause but matches the
  Google path's existing behavior for the same condition).
- *Money-flow axis:* no writes anywhere in this tranche; restore rows never
  touch ledger data.

**Tests (RED first).** `profile_account_card_test.dart:207-219` ("restore
rows hidden (discard-shell unsafe)") pins the OLD contract and must be
INVERTED, not deleted — and the file-header visibility matrix (:4-8), which
documents "anon + groups → restore hidden" as intentional, updated to the new
contract (Gate P2). New/changed cases: (a) anon + 1 group → rows VISIBLE
(fails today); (b) anon + 1 group + tap email row → stays on profile,
`restoreBlockedHasData` snack shown, no `/recover` push (fails today — row
absent); (c) anon + no groups → tap email row pushes `/recover` (unchanged);
(d) durable user → rows absent (unchanged). The
`find.text(restoreBlockedHasData)` pattern exists at
`google_restore_guard_test.dart:99-100`.

## Out of scope (deliberate)

- Activity tab pagination / expense entries in the feed (write path + schema —
  Gate-category product decision, tranche 3).
- The home empty-state restore CTA (by definition only renders with zero
  groups; nothing to fix).
- Durable-credential-sheet conflict-switch surfaces (#661) — already gated,
  not an audit finding.
- Activity empty-state CTA (separate polish finding, not in this tranche).

Delivery: one PR, `Closes` a tranche-2 tracking issue. No Gate-category paths
touched (no money math, rules, functions, router, models).

## Gate record

Round 1 (fresh-context Opus, 2026-07-02): **no P1s** — the reviewer's
adversarial pass on the #647/#648/#661 swap-safety axis failed to refute
Item 3 (gates at the swap untouched; the tap-time check is strictly
additional and more race-correct than the old visibility read). 4×P2 + 2×P3
findings — all test-coverage/contract-precision gaps in this spec, applied
above: invert `profile_account_card_test.dart:207-219` + header matrix,
rewrite the 5-cap test, replace the false "overflow tests guard" claim with a
new narrow-width test, correct the gate call contract (+ `context.mounted`),
split constant placement by import direction.
