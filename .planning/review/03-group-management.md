# Group Management Bugs — HIGH

**4/5 FIXED | 1 partially fixed (non-atomic create/join is a Firestore constraint)**

## ~~8. Group Join Has No "Already a Member" Check~~ FIXED

Now checks `memberIds.contains(uid)` before creating member doc. Throws `'Already a member'` on duplicate.

## ~~9. Leave/Delete Group Ignores Outstanding Balances~~ FIXED

`_executeLeave` checks current user's balance — blocks with "Settle up before leaving" if non-zero. `_executeDelete` checks if ANY member has outstanding balance — blocks with "All members must settle up" dialog.

## ~~10. Fire-and-Forget Deletes with Immediate Navigation~~ FIXED

All three locations now properly await delete operations with try/catch. Navigation only on success. Error snackbar on failure. `context.mounted` guards before navigation.

- `event_danger_section.dart` — awaited + try/catch
- `group_danger_section.dart` — awaited + try/catch
- `group_members_section.dart` — awaited + try/catch

## ~~13. Auto-Select Tab Hijacks User~~ FIXED

Added `_hasAutoSelected` guard. Auto-select runs only once per screen lifecycle, even with reactive Firestore updates.

## 21. Non-Atomic Group Create/Join — PARTIALLY FIXED (by design)

Firestore security rules require `memberIds` to contain the user before member subcollection writes succeed. This makes WriteBatch impossible — step 1 (update memberIds) must commit before step 2 (create member doc). Documented as architectural constraint. If step 2 fails, recovery is possible on retry. Real fix requires Cloud Functions.

## Files Involved

- `lib/features/groups/providers/group_provider.dart`
- `lib/features/groups/widgets/group_danger_section.dart`
- `lib/features/groups/widgets/group_members_section.dart`
- `lib/features/groups/screens/group_settle_up_screen.dart`
- `lib/features/events/widgets/event_danger_section.dart`
