# E2 — Encrypt the local SQLite cache (design + phased plan)

**Status:** design, not yet implemented. Tracked as a separate branch
sprint after the `saffron-fanout` hardening pass lands.

## Why

Today `lib/core/services/local_database.dart` opens `safar_cache.db` with
`sqflite`, which writes the file to the app's private storage in
plaintext. On Android this is `/data/data/com.safar.safar/databases/`,
on iOS the `Documents/` directory of the app sandbox. The OS sandboxes
that path on a healthy device, but:

- A **rooted Android** or **jailbroken iOS** device exposes the file to
  any user-installed tool — and the cache holds participant names,
  expense descriptions, notes, and balances for every group the user is
  in.
- An **encrypted Android backup** that gets restored on a different
  device (or recovered through a forensic tool) leaks the cache in
  plaintext.
- Anyone with **physical device access** plus a debug bridge connection
  can `adb pull` the file from a debug-signed build.

Encrypting the file at rest closes those holes. Firestore data in
transit is already TLS, and Google Cloud encrypts the server-side store
— this gates the only remaining plaintext copy of group data.

The cache is **regenerable** — every row is a snapshot of a Firestore
document the app re-fetches on next sync. That removes the hardest part
of an encryption migration: there is no source-of-truth data to
preserve. A bad key just means the cache rebuilds on next launch.

## What we keep, what changes

Current cache architecture (per `CLAUDE.md`):

- `LocalDatabase` (Sqflite): one DB file, version 8, opened once at
  app start.
- Seven cache repositories under `lib/core/services/cache/` own
  reads/writes for one domain each (trips, expenses, settlements,
  participants, activity logs, categories, groups, group members,
  group ledger).
- Firestore SDK persistence handles the actual offline write queue —
  the cache is a fast-read snapshot layer, not the write path.

**Stays:** the seven repository APIs, the `safar_cache.db` migration
chain, the v8 schema, every consumer in `lib/features/`.

**Changes:** the single `LocalDatabase._open` factory, the package
dependency, a new key-bootstrap on first run, and any test that
constructs `LocalDatabase` directly.

## Stack swap

Replace `sqflite` with `sqflite_sqlcipher`:

```yaml
# Remove
sqflite: ^2.4.2
# Add
sqflite_sqlcipher: ^3.3.1   # mirrors sqflite's API
sqlcipher_flutter_libs: ^0.6.5  # ships the native SQLCipher binary
flutter_secure_storage: ^9.2.2  # platform keystore for the DB key
```

`sqflite_common_ffi` stays for desktop / test runners — the FFI backend
does not support SQLCipher, so tests will run against the unencrypted
FFI backend with the encryption layer no-op'd (see Test impact below).

`sqflite_sqlcipher` is a near-drop-in: same `Database` class, same
`openDatabase` signature plus a `password:` parameter. The repository
files do not change.

### Native side

**Android (`android/app/build.gradle.kts`):** `sqlcipher_flutter_libs`
pulls in `net.zetetic:sqlcipher-android` via its embedded Gradle
metadata. Minimum SDK already 21 in `pubspec.yaml`, which clears the
plugin's `minSdkVersion 19` floor. No manual changes expected; verify
in CI on the first build.

**iOS (`ios/Podfile`):** the plugin transitively brings the
SQLCipher CocoaPod. Pod install runs as part of `flutter run`. Minimum
deployment target already iOS 13 in the project, which clears the
plugin's iOS 11 floor.

**App size:** the SQLCipher native binary adds roughly 1.4 MB per ABI
on Android (so ~3 MB to a universal AAB) and ~700 KB on iOS. The
release `appbundle` already uses ABI splits, so per-user download cost
is closer to 1.4 MB on Android.

## Key bootstrap

Goal: each install gets a fresh 256-bit random key, persisted to the
platform keystore via `flutter_secure_storage`, accessible only to this
package's UID (Android Keystore-backed, iOS Keychain with
`accessibility: first_unlock_this_device`).

### First launch

1. Check `flutter_secure_storage` for key `safar.cache.db_key`.
2. If missing, generate a 32-byte cryptographically random value (use
   `dart:math`'s `Random.secure()` — backed by the OS RNG).
3. Encode as hex, store under `safar.cache.db_key`.
4. Open the DB with that key.

### Subsequent launches

1. Read `safar.cache.db_key`.
2. Open the DB with that key.

### Key loss

If the keystore entry is missing or unreadable (factory reset of the
keystore, OS update bug, ROM swap), opening the DB throws
`DatabaseException('file is not a database')`. Recovery:

1. Catch the open failure.
2. `File(dbPath).delete()` the existing cache.
3. Generate a new key, store it, re-open the DB — runs the v8 init
   schema fresh.
4. Background sync rebuilds the snapshots from Firestore on next read.

The user sees a brief loading state on the first screen after the
reset; no data loss, since Firestore is the source of truth.

### Threat model on the key

A platform-keystore-backed key is not extractable from a non-rooted
device. On a rooted device, both the keystore key AND the encrypted DB
are accessible to a privileged attacker, so the user has lost the
device anyway. The encryption raises the bar for casual `adb pull` or
backup-restore extraction — that's the goal.

We deliberately do NOT derive the key from a user passphrase. Rihla has
no user accounts (anonymous Firebase Auth only), so there is no
existing passphrase to derive from, and prompting for one would defeat
the zero-friction product model.

## Migration on existing installs

Pre-launch, there are no real users to preserve, so the simplest
correct path is:

1. On first run after the upgrade, detect the existing unencrypted
   `safar_cache.db`.
2. Delete it (`File(dbPath).delete()`).
3. Generate a new key, open a fresh encrypted DB at the same path with
   the v8 init schema.
4. Let normal Firestore streams refill the cache on next read.

If this ships post-launch and the install base is non-trivial, swap
step 2 for a one-shot dump-and-reload:

1. Read every row from the unencrypted DB through the old `sqflite`
   factory.
2. Write each row through the encrypted factory.
3. Delete the unencrypted file.

Add a one-shot SharedPreferences flag (`safar.cache.v8_to_v9_complete`)
so the migration runs exactly once.

## Test impact

`sqflite_common_ffi` does not support encryption. Tests have two
options:

- **Option A (recommended):** inject the database factory at the
  `LocalDatabase` boundary. Production wires the encrypted factory;
  tests wire the unencrypted FFI factory with a no-op key. The
  repository layer never sees the difference.
- **Option B:** add `sqflite_sqlcipher_ffi` (community-maintained, less
  stable). Match production exactly. Slower test boot. Not worth the
  hassle for cache-snapshot tests.

Pick A. The injection point already exists — `LocalDatabase` is a
provider-overridable singleton in tests today.

## Phasing (own branch)

Branch suggestion: `feat/sqlite-encryption`. Worktree under
`.claude/worktrees/`.

**Phase 1 — dependencies + key bootstrap (~2h)**
- `pubspec.yaml`: drop `sqflite`, add `sqflite_sqlcipher`,
  `sqlcipher_flutter_libs`, `flutter_secure_storage`.
- New `lib/core/services/cache_key_service.dart` with one-shot
  `getOrCreateCacheKey()` returning a hex string.
- Test: mock `flutter_secure_storage`, assert the key is generated
  once and read on subsequent calls.

**Phase 2 — `LocalDatabase` swap (~2h)**
- Change the `openDatabase` call to pass `password: await
  CacheKeyService.getOrCreateCacheKey()`.
- Wrap the open in a `try/catch` for the key-mismatch path; on catch,
  delete the file and re-open.
- Inject factory for tests.

**Phase 3 — legacy DB cleanup (~30 min)**
- On first launch after upgrade, if a v8 unencrypted DB exists at the
  expected path, delete it. Set the SharedPreferences flag.
- Decision: skip the dump-and-reload migration since this ships
  pre-launch.

**Phase 4 — CI smoke + native plugin verification (~2h)**
- Build `appbundle` with `--obfuscate --split-debug-info` against the
  new plugin stack.
- Run on a physical Android device + iOS simulator.
- Check the DB file with `sqlite3` — it should fail to open without
  the cipher key (correct behavior).

**Phase 5 — release notes + privacy policy edit (~30 min)**
- Privacy policy line 6.4 currently says "The local SQLite cache on
  your device is not separately encrypted." Flip to "The local SQLite
  cache is encrypted with a device-bound key stored in the platform
  keystore."

Total: ~1 day of focused work + half a day of CI / native debugging
margin.

## Risks

- **Plugin conflict.** `cloud_firestore` and `sqflite_sqlcipher` both
  link native code; a CocoaPods version pin or AndroidX conflict
  could land late. CI smoke first.
- **OS keystore quirks.** Android Keystore on some OEM ROMs has
  documented flakiness around key-attestation failures. The
  catch-and-rebuild path covers it, but it might trigger more often
  than expected. Watch crash reports after release.
- **Performance.** SQLCipher's overhead is ~5–15% on writes. Cache
  reads dominate Rihla's DB load and are well under that threshold,
  but profile after the swap.

## Out of scope

- Encrypting Firestore offline persistence (handled by Firebase SDK,
  not configurable per-app).
- Encrypting SharedPreferences (separate effort — for now relies on
  OS sandboxing).
- Key derivation from a user passphrase (no user accounts to bind to).
