# Broken Features — CRITICAL + HIGH

**2/2 FIXED | All resolved**

## ~~5. Memory Photos Never Display~~ FIXED

Added `_urlCache` + `getDownloadUrlCached()` to `MemoryService`. `eventMemoriesProvider` now wraps `watchMemories()` stream with `.asyncMap()` + `Future.wait()` to resolve all download URLs in parallel before emission, populating `signedUrl` via `Memory.copyWith()`. Cache evicted on delete.

## ~~11. Vault Dismissible Fires Before Delete Completes~~ FIXED

Now uses `confirmDismiss` callback that shows AlertDialog before allowing dismiss. Delete only fires after user confirmation. Properly gates the operation.

## Files Involved

- `lib/features/memories/screens/memories_screen.dart`
- `lib/features/memories/models/memory_model.dart`
- `lib/features/memories/services/memory_service.dart`
- `lib/features/vault/screens/vault_screen.dart`
