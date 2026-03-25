# Deployment Readiness Report — 2026-03-06

**Version**: 1.0.1+8
**Branch**: feature/creative-overhaul (2 commits ahead of main)

## Status: Close to Ready

## Passing
- All 16 tests pass
- Flutter doctor — all green
- config.json exists and gitignored
- CI/CD pipeline configured (GitHub Actions -> Google Play alpha)
- Sensitive files (.env, config.json) in .gitignore

## Issues to Fix Before Deploy

### P0 — Must Fix
- [ ] `use_build_context_synchronously` in `command_center.dart:1180` and `:1242` — BuildContext used after async gap, potential crash if widget unmounted
- [ ] Merge `feature/creative-overhaul` to `main` before tagging release

### P1 — Should Fix
- [ ] Unnecessary `!` on non-nullable value in `settle_up_screen.dart:361`
- [ ] Deprecated `Radio` API (`groupValue`/`onChanged`) in `manage_members_screen.dart:509-510` — will break on future Flutter upgrade

### P2 — Low Priority
- [ ] `profilesSampleRate` experimental warning in `main.dart:24` (Sentry)
- [ ] 8x unnecessary double underscore lints across various files

### Notes
- No iOS CI — iOS builds are manual, test on real device before App Store submission
- Android pipeline is solid: tests -> build -> Play Store alpha upload
