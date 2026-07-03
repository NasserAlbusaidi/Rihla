# History PR3 — Search over history (#808 PR3, closes the epic + the audit HIGH)

> **For the implementing agent:** builds ON TOP of merged PR2
> (`docs/plans/2026-07-03-history-pr2-activity-pagination.md`). Re-verify every claim against
> the post-PR2 `main` before coding — PR2's final shape may have drifted from its spec during
> review; the merged code wins.

**Goal:** A search field on the cross-group Activity tab that filters the loaded pages
client-side, with an honest "search older activity" affordance that pulls more pages through
the PR2 paginator. NOT full-text-global search — that stays deferred until there's evidence
it's needed (issue #808's explicit scope line).

**Scope law:** Pure client, Activity tab only. Final PR of the epic → commit body carries
`Closes #808` (squash-merge closes from the COMMIT body, #447 trap). Branch:
`feat/808-pr3-activity-search`.

## Ground truth to re-verify

- PR2's pager state (entries + `hasMore` + `loadMore()`) — the search filters `entries` and
  reuses `loadMore()` verbatim; no new fetch path.
- Search-affordance precedent: `lib/features/ledger/widgets/ledger_search_sheet.dart`
  (query state, `_SearchHit` matching, `ledgerSearchNoMatches*` l10n pattern) and the ledger
  top-bar `Iconsax.search_normal` button (`ledger_screen.dart:528`). Reuse the *pattern*
  (match-fields helper + empty-results copy), not necessarily the bottom-sheet chrome.
- Filter memoization: PR2 keeps the #634-style cache keyed on (list length, filter); the query
  becomes a third key component.

## Design (decided)

- **Affordance:** search icon (RIconButton, ghost) in the tab's top bar toggling an inline
  search `TextField` between the filter strip and the list. Clearing/closing restores the
  plain feed. Autofocus on open; RTL-safe via directional APIs.
- **Matching:** case-insensitive `contains` over, per entry: `log.description`, the LOCALIZED
  display text (`localizedGroupActivityText`), `actorName`, `groupName`,
  `metadata.eventName`, and the formatted amount string when `activityAmount(...)` is non-null.
  Pure function `bool activityMatchesQuery(entry, String query, AppLocalizations l10n)` in a
  unit-testable location — table-driven tests incl. Arabic text, empty query (matches all),
  amount substring, and a description-only match (e.g. "Dinner" hits an `expense_added` whose
  displayed phrase is generic — document this as intended: display text is generic per
  D-PR2-1 but the underlying description remains searchable).
- **Composition:** query AND the active type chip both apply.
- **Load-older affordance:** while a query is active and `hasMore`, the list footer shows
  "Searching {N} loaded entries · Search older activity" (button → `loadMore()`); when there
  are zero matches and `hasMore`, the empty-results state's action is that same button. Zero
  matches and NOT `hasMore` → plain "no matches" empty state. All strings l10n'd (en + ar,
  regen + commit generated files).
- **Keys:** add test keys following the existing keys-file convention for the feature.

## Tests (minimum)

- Unit: `activityMatchesQuery` table (fields above; unicode/Arabic; no crash on null
  actorName/empty metadata).
- Widget: typing narrows the visible rows (Text.rich → `find.textContaining(...,
  findRichText: true)`); "search older" button triggers another page fetch and a
  newly-loaded matching row appears; chip + query compose; clearing the query restores the
  feed; zero-match + hasMore shows the load-older action; virtualization rules (no row
  counting; scroll for presence).
- Update, don't blindly patch, any PR2 tests whose finders the new chrome shifts.

## Verify & hand back (do NOT push)

- [ ] `flutter analyze` clean; `bash tool/check_theme_purity.sh` clean
- [ ] Full `flutter test`
- [ ] l10n generated files committed
- [ ] Conventional commits; ONLY the final commit body carries `Closes #808`
- [ ] Report: worktree path, branch, commits, RED evidence, deviations
