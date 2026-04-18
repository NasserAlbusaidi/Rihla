# Phase 37 — Manual QA Checklist (D-19)

Non-blocking supplement to automated goldens + CI guard + contrast test. Nasser runs this before merge.

## Per-Screen Light/Dark Walkthrough

For each screen below, open in BOTH light and dark mode and verify:

- Text remains readable (no low-contrast surprises)
- No hardcoded colors bleed through (e.g. stark white card on dark background)
- Gradients render with correct theme variant (onboarding pages, ledger hero, activity hero)
- Group avatar slots render with theme-appropriate tints
- Divider/border tokens swap correctly (slate vs. gray)

Screens:

- [ ] Splash / auth retry (expected: always light per research Open Q 2)
- [ ] Onboarding pages 1-3
- [ ] Home (groups list)
- [ ] Create Group
- [ ] Join Group
- [ ] Group Detail (CommandCenter — dashboard)
- [ ] Group Settings
- [ ] Group Settle Up
- [ ] Group Activity feed
- [ ] Event Create (type picker + form)
- [ ] Event Command Center
- [ ] Ledger (expenses list + hero gradient)
- [ ] Add Expense form
- [ ] Edit Expense form
- [ ] Settle Up (event-level)
- [ ] Gear
- [ ] Logistics
- [ ] Vault (documents)
- [ ] Memories (photo grid)
- [ ] Settings > Profile
- [ ] Settings > Display (new!)
- [ ] Theme picker bottom sheet (System / Light / Dark radio)

## Theme Toggle UX

- [ ] Open Settings > Display > Theme
- [ ] Currently shows "System • Following device" (default)
- [ ] Tap → bottom sheet slides up with 3 radio options
- [ ] Tap "Dark" → sheet dismisses → app instantly switches to dark theme → no white flash
- [ ] Reopen Theme tile → trailing shows "Dark"
- [ ] Force-quit app, reopen → still in dark (persistence verified)
- [ ] Return to System → OS-level toggle switches app theme in realtime

## OS Chrome

- [ ] Status bar icons: light theme → dark icons; dark theme → light icons
- [ ] Android navigation bar: light theme → warm sand background; dark theme → slate background
- [ ] Transition from light → dark does not show a one-frame flash of the wrong chrome

## Edge Cases

- [ ] Offline banner renders correctly in both themes
- [ ] Skeleton loading states visible in both themes
- [ ] Empty states (no groups, no expenses, no gear) readable in both themes
- [ ] Error states (network error, form validation) readable in both themes
- [ ] Dialogs and bottom sheets honor the active theme
- [ ] Snack bars readable in both themes
- [ ] Keyboard-open states (Add Expense, Edit Name sheet) render input fields with theme-correct border/fill

## Accessibility Spot Checks

- [ ] Small-type text (bodySmall/labelSmall) legible in dark mode (B4 correction — now routed through textSecondary in both themes)
- [ ] Muted decorative glyphs (textMuted) remain faint but readable enough to be meaningful
- [ ] Primary CTAs have sufficient contrast against surrounding surfaces in both themes
- [ ] Module accent colors (Ledger = primary teal; all others = gray) consistent across themes

## Automation backstop (should all be green before manual QA)

```
flutter analyze                                     # expect 0
flutter test                                        # full suite, includes goldens + contrast
flutter test test/goldens/                          # expect 0
bash tool/check_theme_purity.sh                     # expect 0
flutter test test/unit/dark_theme_contrast_test.dart  # expect 0
```
