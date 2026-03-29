# Deferred Items — Phase 17

## Resolved Issues

### gear_screen_mutations_test.dart overflow (8 tests) — RESOLVED

**Root cause:** `SkeletonLoader.cardList()` (used by gear_screen) with the new Column-based
`build()` method caused RenderFlex overflow in `Expanded` containers. Column expands to natural
height (5 items x ~84px = ~420px) exceeding the bounded parent viewport.

**Fix (commit `38041e1`):** Wrapped Column in `SingleChildScrollView(NeverScrollableScrollPhysics())`
— clips overflow in bounded contexts, preserves Column layout in unbounded contexts.

**Status:** All 694 tests passing as of 2026-03-29.

---

No open deferred items.
