# Remove Auth: Anonymous Device Identity Design

**Date:** 2026-03-07
**Approach:** Supabase Anonymous Auth (signInAnonymously)
**Inspiration:** Splid — no login, name-based members, sync via invite codes

## Summary

Replace email/password authentication with Supabase anonymous sign-in. Users never see a login screen. The app silently creates an anonymous identity on first launch. Trip members are names, not accounts. Devices claim a name when joining a trip. All existing RLS policies stay intact because `auth.uid()` still works.

## Identity & First Launch

- App calls `supabase.auth.signInAnonymously()` during bootstrap, before router evaluates
- Anonymous session persisted by Supabase SDK across restarts
- `currentUserProvider` still returns a `User` (without email)
- No login UI, no registration, no password reset

### Removed
- `login_screen.dart`, `forgot_password_screen.dart`, `reset_password_screen.dart`
- `authModeProvider`, `authLoadingProvider`, `authErrorProvider`
- Sign up/sign in logic in `AuthService`
- Deep link scheme `io.supabase.rihla://reset-password`

### Kept
- `authStateProvider` — listens to anonymous auth state
- `currentUserProvider` — provides the anonymous `User`
- Bootstrap auto-sign-in guarantees session exists

## Trip Members: Name-Based

All members are names. Devices claim names.

### Flow — Creating a Trip
1. Creator enters trip name + member names (including their own)
2. Creator picks which name is theirs
3. Creator's `auth.uid()` written to that participant with `LEADER` role
4. Remaining names stay unclaimed

### Flow — Joining a Trip
1. Joiner enters invite code
2. Sees list of unclaimed names
3. Picks their name
4. Their `auth.uid()` written to that participant row
5. Full sync begins

### Data Model
- `participants.user_id` remains nullable (already is for shadows)
- `is_shadow` flag loses meaning — all members start unclaimed
- `is_trip_member()` RLS function works once a device claims a name
- Expense/gear/logistics all reference `participant_id`, not `user_id` — no changes needed

## Router & Navigation

### Removed Routes
- `/login`
- `/forgot-password`
- `/reset-password`

### Kept Routes
- `/home`, `/create-trip`, `/join-trip`, `/settings`
- Onboarding route

### Redirect Logic
- Not onboarded → onboarding
- Otherwise → home
- No auth check needed (bootstrap guarantees anonymous session)

## Settings & Profile

### Removed
- Change password, logout
- Global display name / avatar
- `profiles` table usage (no global identity)

### Kept / Added
- App preferences (theme, notifications)
- Trip-specific settings
- Optional device name in SharedPreferences — pre-fills when creating/joining trips

## Module Impact

| Module | Change Level | Notes |
|--------|-------------|-------|
| Ledger | None | Uses `participant_id` for payer/splits |
| Gear | None | Assignment by `participant_id` |
| Logistics | None | Trip-scoped, no user dependency |
| Vault | Minor | Keep `auth.uid()` for `uploader_id`, resolve display name via participant lookup |
| Memories | Minor | Same as Vault for `uploaded_by` |
| Activity Logs | Minor | Keep `auth.uid()` for `actor_id`, resolve display name via participant lookup |
| FCM | None | Token binds to anonymous `auth.uid()` |
| Sync/Cache | None | `downloadTrips(userId)` passes anonymous `auth.uid()` |

## RLS Policies

No changes needed. All 54 `auth.uid()` checks work with anonymous users. `is_trip_member()` function works because `participants.user_id` is set when a device claims a name.

## Database Changes

- Enable anonymous sign-in in Supabase dashboard (Auth > Settings)
- `profiles` table: can be dropped or left unused
- `participants`: no schema change needed (`user_id` already nullable)
- `is_shadow` column: can be deprecated (all members start unclaimed)
- No new migrations required for core functionality

## Risks

- **Device loss = identity loss** — if a user wipes their phone, their anonymous `auth.uid()` is gone. They'd need to re-join trips and reclaim a name. Consider: allow "unclaiming" a name so another device can reclaim it.
- **No account recovery** — by design. This is the Splid trade-off.
- **Supabase anonymous user limits** — check project plan for anonymous user quotas.
