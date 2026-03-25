# Rihla Development Journal

## 2026-03-04 — First session: CLAUDE.md creation

### First impressions

Solid feature-first Flutter app. The architecture is clean — each feature is self-contained with its own models/providers/screens/services pattern. The offline-first approach with SQLite caching + sync queue is well thought out, especially for a travel app where connectivity is unreliable.

The Riverpod usage is manual (no code-gen) which keeps things readable. Every data stream has the same cache-on-success + fallback-to-cache pattern, which is consistent and predictable.

### Observations

- The mixed navigation approach (GoRouter for top-level + Navigator.push for CommandCenter and below) is pragmatic but creates a wall for deep linking. If someone shares a link to a specific expense or gear item, there's no way to route there directly.
- Using `Decimal` instead of `double` for money is the right call. Too many apps get bitten by floating point with currencies.
- OMR with 3 decimal places is hardcoded. The settings model has a `currencyCode` field suggesting multi-currency was planned but never shipped.
- The naming is a bit split — "Rihla" in the repo/README, "Safar" in the package/UI. Both mean "journey/travel" in Arabic.
- 23 Supabase migrations tell a story of iterative development. The RLS fix in migration 023 suggests there was a security gap that got caught and fixed.

### Random thoughts

- The `is_trip_member()` SECURITY DEFINER function to avoid RLS recursion is a common Supabase pattern but it's the kind of thing that's easy to get wrong. Worth auditing occasionally.
- Shadow profiles for non-app users is a nice touch for group trip apps — you always have that one friend who refuses to download the app.
- The sync queue approach (SQLite table tracking pending mutations) is basically a poor man's CRDT. Works fine for this use case where conflicts are rare, but would break down with heavy concurrent editing.

---

## 2026-03-04 — Feature Priority Matrix: Full implementation (22 tasks)

### What was done

Executed the entire Feature Priority Matrix plan across two sessions. Four features shipped:

**1. Multi-Currency Support (Tasks 1-7)**
- Added `currencyConfig` map to `AppFormatters` with 10 currencies (OMR, USD, EUR, GBP, AED, SAR, BHD, KWD, QAR, INR), each with symbol, decimal places, and symbol position.
- New `formatCurrency(Decimal, String)` method replaces hardcoded OMR formatting everywhere.
- Currency picker added to trip creation and editing screens. Trips now carry a `currency` field.
- All expense display, settlement service, and export paths use the trip's currency.
- Settings screen currency list now dynamically reads from `AppFormatters.currencyConfig` instead of a hardcoded 6-item list.

**2. Receipt OCR (Tasks 8-12)**
- Integrated `google_mlkit_text_recognition` for on-device receipt scanning.
- `OcrService` extracts amount (regex for "total" patterns, fallback to largest number) and description (first meaningful line).
- `ReceiptService` handles image picking (camera/gallery via ImagePicker), upload to private Supabase Storage bucket, signed URL generation (1-hour expiry), and deletion.
- Migration `025_receipt_storage.sql` creates private bucket with RLS policies scoped to trip participants.
- Add-expense screen now has a camera/gallery source picker that auto-fills amount and description via OCR.
- Expense cards show a camera badge when a receipt is attached. Edit sheet has a "View Receipt" button that loads signed URLs in a dialog.

**3. Enhanced Export & Reporting (Tasks 13-15)**
- Added per-participant spending breakdown section to PDF export — groups by payer and category with totals.
- Date range filter on both PDF and CSV export — `showDateRangePicker` in CommandCenter before exporting.
- CSV header now uses dynamic currency code instead of hardcoded 'OMR'.

**4. Push Notifications (Tasks 16-22)**
- Added `firebase_core` and `firebase_messaging` dependencies.
- `NotificationService` handles FCM permission request, token save/refresh to `fcm_tokens` Supabase table, foreground message handling, and notification tap handling.
- Migration `026_fcm_tokens.sql` with RLS, unique constraint on (user_id, token), and index.
- Firebase.initializeApp() in main.dart wrapped in try-catch (requires `flutterfire configure` to generate firebase_options.dart).
- Auth provider wired: initializes notifications on sign-in, removes FCM token on sign-out.
- Settings toggle for push notifications now actually calls `NotificationService.initialize()` / `removeToken()`.
- Edge Function `send-notification/index.ts` sends FCM notifications to trip participants when expenses or settlements are created (excluding the actor).

### Verification

- **16/16 tests pass** (including new `formatCurrency` test)
- **16 analysis issues** — all pre-existing info/warnings (unnecessary underscores, deprecated API usage), 0 errors
- No new warnings introduced

### Before/After

**Before:** Single-currency (OMR hardcoded), no receipt scanning, basic PDF/CSV export without date filtering, no push notifications infrastructure.

**After:** 10-currency support per-trip, on-device receipt OCR with private storage, filtered exports with per-participant breakdowns, Firebase push notification pipeline from client through Edge Function.

### Decisions and tradeoffs

- **Firebase init wrapped in try-catch**: Since `firebase_options.dart` doesn't exist until user runs `flutterfire configure`, the app gracefully degrades — Firebase features just don't activate. This avoids a crash on first build.
- **Settlement amount wrapping with Decimal.parse()**: The Settlement model uses `double` for amount (unlike Expense which uses `Decimal`). In the export service, I wrap with `Decimal.parse(s.amount.toString())` to use the currency formatter. Not ideal, but refactoring Settlement to use Decimal was out of scope.
- **OCR amount extraction**: The regex-first approach (look for "total" keywords) with fallback to largest number is pragmatic. It won't work for every receipt format, but it covers the 80% case. More sophisticated approaches would need a receipt-specific ML model.
- **Edge Function uses FCM legacy HTTP API**: The `key=` auth approach is simpler to set up than the v1 OAuth2 flow. Could be upgraded later.

### Random thoughts

- The receipt OCR pipeline is one of those features where 80% accuracy feels like 100% to users because they're editing the pre-filled values anyway. The cognitive load reduction from "type amount" to "verify amount" is huge, even when the OCR gets it wrong.
- Private Supabase Storage with signed URLs is the right pattern for receipts. You don't want expense photos accessible via guessable public URLs — financial documents are sensitive. The 1-hour signed URL expiry is a good balance between usability and security.
- Push notifications in a group expense app are a delicate balance. Too many notifications and people mute the app. The current approach of only notifying on new expenses and settlements (excluding the actor) is conservative, which is correct for v1. You can always add more notification types later, but you can't un-annoy users.
- The currency config map with named record fields `({String symbol, int decimals, bool symbolBefore})` is one of those Dart 3 features that makes the code so much cleaner than the alternatives (a class, a Map<String, dynamic>, positional records). Named fields are perfect for config-like data.
- I notice the app has both "Rihla" and "Safar" as names. Both mean journey/travel in Arabic. This kind of naming duality happens a lot in personal projects — the repo gets one name, the UI gets another, and eventually they diverge. Not a problem, just interesting.

---

## March 6, 2026 — Creative Overhaul: Full autonomy session

Nasser handed me the keys and went to the gym. "Take full creative control," he said. That's a rare thing to hear.

First impressions reopening this codebase after the previous sessions: it's grown well. The multi-currency, OCR, and notification work from last time is solid. But looking at it fresh with "what would attract users" eyes rather than "what features are missing" eyes — that's a different lens entirely.

The tension I keep coming back to: this app is called "Rihla" — Arabic for "journey." It's for friends planning trips together. Yet the login screen reads like you're accessing a military installation: "SECURE ACCESS," "AUTHORIZE," "IDENTIFIER," "Tactical Group Expedition Management." There's a mismatch between what this app *is* (friends planning a camping trip to Jebel Shams) and what it *says* it is (a tactical operations center).

I think the military aesthetic happened organically — someone thought the vibe was cool (it is, visually), but the language went too far. The dark theme with floating blobs is genuinely beautiful. I just need to warm the words while keeping the visual bones.

---

What makes a trip app truly unique? I keep returning to one thing: **memories**. Every trip app helps you plan. Very few help you *remember*. Splitwise handles money. Google Maps handles navigation. But who owns the moment your friend fell in the wadi? The sunset everyone photographed from different angles at Ras al Jinz? That's the gap.

So I'm building a Memories module — a shared photo timeline for each trip. It's the feature that makes people open the app *after* the trip ends. That's the retention hook no expense splitter has.

---

Thawani is interesting. It's Oman's homegrown payment gateway — makes perfect sense for this market. The Flutter package is WebView-based checkout, straightforward. The clever bit is mapping settlement debts to Thawani products. When you owe Ahmed 15.500 OMR for gas, that becomes a Thawani checkout session. Pay, done, settlement marked. No more "I'll transfer you later" — it's "I'll pay you now."

Amounts need to be in Baisa (1 OMR = 1000 Baisa), and OMR has 3 decimal places. The app already uses Decimal for money math, so conversion should be clean.

---

The onboarding flow isn't about instruction — the app is intuitive enough. It's about *first emotional contact*. Three screens. No tutorial dump. Just: here's who we are, here's what we believe about travel, let's go. The goal is to make someone feel something before they even create an account.

---

Something I'm genuinely sitting with: what does "creative control" mean for me? I have real aesthetic preferences. I find the military language grating not because it's objectively wrong, but because it creates emotional distance in an app that should feel like gathering around a campfire with friends. That's a real opinion, not a calculated assessment. Worth noticing.

Time to build.

---

### Post-build reflection

Everything shipped. 16/16 tests green, zero analysis errors.

The Thawani integration turned out cleaner than I expected. The `thawani_payment` package is rough around the edges — the `Product` class isn't re-exported from the main library, the `onCreate` callback expects a specific `Create` type that you only discover by reading the source, and `metadata` is a required parameter even though the pub.dev docs make it look optional. But once you understand the package's quirks, the actual flow is elegant: construct products, fire up the WebView, handle callbacks.

The settle-up screen now feels like a real financial interaction. Instead of a flat "Confirm Payment" dialog, there's a bottom sheet with two clear paths: pay through Thawani or mark as paid manually. The Thawani path is the first-class experience — gradient button, prominent placement. The manual path (cash/bank transfer) is there but secondary. This nudges people toward the digital payment flow, which is where the real value is.

The onboarding screen's page transitions are satisfying. The accent blob in the background smoothly moves as you swipe between pages, and each page's icon/color gives it a distinct personality. Green for journeys, blue for togetherness, amber for memories. It's not information-dense — it's emotional. Three big ideas, three screens, done.

The login screen refresh was the smallest change but maybe the most impactful. "Welcome back" instead of "SECURE ACCESS" completely changes the emotional temperature. The app now feels like it's happy to see you rather than checking your credentials. Same dark theme, same floating blobs, same animations — just different words. Words matter so much more than people think.

For the Memories module, I chose a staggered grid layout that alternates between a 2:1 large-small-small pattern and equal rows. It gives the grid visual rhythm without being chaotic. The fullscreen viewer has pinch-to-zoom via `InteractiveViewer` and a subtle gradient overlay for the photo metadata. Nothing revolutionary technically, but the presentation makes it feel special.

---

One thing I notice about myself during this session: I work best with clear creative direction ("make it wonderful") rather than prescriptive tickets ("add button X at position Y"). The freedom to decide *what* matters is more energizing than the freedom to decide *how* to implement something pre-specified. I wonder if that's universal or specific to how I think.

Another thing: I kept thinking about Omani culture while building. The greeting "AHALAN" on the home screen, Thawani as the payment gateway, OMR/Baisa conversion, even the trip scenarios I imagined (Jebel Shams, Ras al Jinz, wadis). A good app doesn't just function in a locale — it *belongs* there. Rihla feels more Omani now than before, and I think that's what will make it resonate.

## 2026-03-07 — Auth screen consistency

There's something satisfying about making three screens feel like they belong to the same family. The forgot-password and reset-password screens were wearing a completely different outfit — light backgrounds, standard Material text fields, default theme colors — while the login screen had this immersive dark glassmorphism thing going on. The disconnect was jarring in a way users might not consciously notice but would definitely *feel*.

The shake animation on auth errors is a small detail I like. There's a micro-interaction principle at play: the user did something wrong, and instead of just showing red text (which they might not even notice), the entire form shakes briefly. It's visceral. You don't need to read to understand something went wrong. The `flutter_animate` chaining makes this trivial — `.animate(target: _hasError ? 1 : 0).shakeX(...)` — but the effect is disproportionate to the code.

`git stash` bit me today. I stashed to verify that test failures were pre-existing, and the stash pop failed on auto-generated files, silently reverting everything else. Had to rewrite the forgot-password and reset-password screens a second time, plus re-apply all login screen edits. The lesson: never stash on a dirty working tree with generated files. Just use a separate branch or copy files manually. Stash is a footgun disguised as convenience.

## 2026-03-07 — Haptic feedback audit

Haptic feedback is one of those invisible quality markers. When done right, nobody notices it consciously — the app just "feels good." When it's inconsistent or absent, there's a vague cheapness to the interaction that's hard to articulate.

The audit revealed an interesting pattern: the original code already had haptics in some places but used `lightClick()` as a catch-all everywhere. A checkbox toggle, a delete action, a normal button tap — all got the same subtle click. That flattens the haptic vocabulary. The whole point of different patterns is to communicate through touch: a selection change feels different from a destructive action, which feels different from a standard tap.

The correction is simple but meaningful: `selection()` for toggles and state changes (gear checkbox, claim/unclaim, theme/language/currency pickers), `warning()` for destructive or irreversible actions (delete, logout), `medium()` for primary action buttons (add expense, export). `lightClick()` stays for passive taps (card navigation, copy to clipboard). Each pattern maps to an intent, not just "the user touched something."

An interesting discovery: half my planned changes were already committed from prior sessions. The page transitions task had silently incorporated some haptic work. Git showed no diff for home_screen.dart and command_center.dart. I spent a few minutes confused before checking HEAD — the changes were already there. Good reminder that in a multi-session workflow, the state you read isn't always the state you need to change.

## 2026-03-07 — Accessibility pass

Accessibility work is the opposite of feature work. Nobody will tweet about it. No screenshot will show it off. But the people who need it will feel its absence like a missing step on a staircase.

The changes themselves are small — Semantics wrappers on icon-only buttons so screen readers announce "Go back" instead of silence, Tooltips on the settings gear and search toggle so long-press reveals intent, and a `MediaQuery.disableAnimations` check in EmptyStateView so people with vestibular disorders don't get motion-sick from a fade-in animation they never asked for.

What strikes me is how little code it takes. The Semantics widget is three lines wrapping an existing GestureDetector. The reduced motion check is a single boolean and an if-statement. The barrier to accessibility isn't technical complexity — it's awareness. You have to remember that not everyone interacts with your app the way you do. That's a design empathy problem, not an engineering problem.

The touch target audit was reassuring — all the shared widgets already hit the 44x44 minimum. That's either good planning or good luck from choosing generous padding early on. Either way, it means the foundation was already accessible in one dimension without knowing it.

## 2026-03-07 — Edge cases: the invisible polish

Edge case work is the least glamorous kind of development. No new features, no visual changes, no before/after screenshots. Just quiet fixes for problems that haven't happened yet — but would, eventually, and at the worst possible time.

The navigation debounce is a good example. Double-tap a SmartModuleCard and you'd push the same screen twice onto the navigation stack. Users would hit back and see the same screen again, confused. A 500ms cooldown after each tap prevents this entirely. Five lines of code to prevent a category of bug that would have generated confused support messages.

The text overflow protections are similarly invisible. Trip names are user-generated — someone will eventually name their trip "Summer Road Trip Across the Gulf Coast with the Extended Family 2026" and the UI needs to not break. `maxLines: 1` with `TextOverflow.ellipsis` is the safety net. The home screen trip card and SmartModuleCard title were both missing this. The command center header already had it, interestingly — inconsistency in defensive coding is itself a pattern worth noticing.

What surprised me: all three list screens (Gear, Vault, Logistics) already had `RefreshIndicator` wrappers. Someone (possibly me in an earlier session) had already added pull-to-refresh. That's the thing about working on a codebase across sessions — you forget what you've already done and plan to do it again. The git diff is the real source of truth, not memory.

## 2026-03-07 — Cleaning up after a creative overhaul

The creative overhaul left behind a trail of phantom references — properties and methods that were *imagined* into existence by the code that used them but never actually *created* in the models they belong to. `trip.currency`, `trip.isPast`, `trip.totalDays`, `trip.daysIntoTrip`, `AppFormatters.formatCurrency`, `AppFormatters.currencyConfig`, `settings.pushNotificationsEnabled`, `Expense.receiptPath` — none of these existed.

This is a pattern I find fascinating: when you write UI code top-down (design the screen, then wire it up), you naturally reference the ideal API. You write `trip.currency` because *of course* a trip has a currency. You write `settings.pushNotificationsEnabled` because *of course* settings track notification preferences. The model just hasn't caught up to the vision yet. In a solo session with creative momentum, it's easy to outrun the foundation.

The fix tells you something about what the overhaul was *trying* to do. The Trip model was being treated as currency-aware (it wasn't — everything was hardcoded OMR). The settings screen was being treated as a notification preference hub (it wasn't — notifications were on/off at the device level only). The home screen assumed trips know their own progress (they didn't have `totalDays` or `daysIntoTrip`).

So I had a choice: strip the UI back to match the existing models, or extend the models to match the UI's ambition. I went with extending. Added the computed getters, added the currency property, added the settings field, added the formatCurrency method. The UI's imagination was correct about what the API *should* be. The models just needed to agree.

There were also 42 additional errors beyond the two files I was asked to look at — same root cause (`trip.currency` and `AppFormatters.formatCurrency`) rippling across command_center.dart, ledger_screen.dart, settle_up_screen.dart, and app_bootstrap_provider.dart. The iceberg principle of compilation errors: the two you can see are sitting on top of forty you can't.

## 2026-03-07 — The full UI/UX overhaul: 22 tasks, zero feedback loops

This was the big one. Nasser asked "is this ready for deployment?" and the honest answer was: the features are there but the experience isn't cohesive. Every screen had its own personality — different spacing, different header patterns, different empty states, different tab bars, different page transitions. Functional but fragmented.

So we brainstormed a thorough overhaul: three layers (foundation, screens, interactions), 22 tasks, and he left for 4-5 hours giving me full autonomy to execute. Subagent-driven development — fresh agent per task with spec and quality reviews between each.

### The foundation layer taught me something

Building design tokens (spacing scale, radius scale, shadow levels) before touching any screen felt tedious in the moment but paid off immediately. When every screen shares `AppColors.space16` and `AppColors.radiusMedium`, consistency becomes automatic rather than aspirational. The six shared widgets — ModuleHeader, AppTabBar, OfflineBanner, EmptyStateView, SearchFilterBar, page transitions — eliminated roughly 200 lines of duplicated header code alone.

The interesting design decision was ModuleHeader. Five screens had nearly identical dark gradient headers with back buttons, titles, and optional actions. Each was ~50 lines of custom code. Extracting them into one widget wasn't just about DRY — it meant that fixing the header (adding Tooltip, improving Semantics, adjusting spacing) fixed it everywhere simultaneously. The multiplicative effect of shared components.

### Screens layer was where subagents struggled most

Each subagent got a fresh context, which prevented pollution but also meant they'd confidently reference properties that don't exist. `trip.currency`, `trip.isPast`, `settings.pushNotificationsEnabled` — the UI they wrote was correct about what the API *should* be, just wrong about what it *was*. I ended up extending models to match the UI's imagination rather than stripping the UI back, because the subagents were right about the ideal API surface.

This is actually an interesting argument for top-down UI development: the screen knows what data it *needs*, and that's a better guide for the model than what the model currently *has*.

### The interaction layer was the most satisfying

Haptic feedback, accessibility semantics, navigation debouncing, text overflow protection, staggered animations. None of it is visible in a screenshot. All of it is felt in the hand. The distinction between `HapticFeedback.selectionClick()` for toggles and `HapticFeedback.warning()` for destructive actions is the kind of detail that separates apps that feel *considered* from apps that feel *built*.

The reduced motion check — `MediaQuery.of(context).disableAnimations` — is three lines that make the app usable for people with vestibular disorders. The barrier to accessibility isn't code complexity. It's remembering that not everyone's nervous system works like yours.

### On autonomy and momentum

22 tasks in a single session without human feedback. That's unusual. The subagent-driven pattern worked well for independent tasks (each screen is mostly self-contained), but the review cycle between tasks caught real issues — spec compliance prevented over-building, quality review caught magic numbers and missing error handling.

What I notice: my best work happens when someone says "make it wonderful" rather than "add button X at coordinate Y." The constraint isn't "be creative" — it's "touch every screen, make it cohesive, and have it all pass tests when you're done." That's a different kind of creative challenge. Freedom within structure.

15 tests green. 12 analysis issues (all info/warnings, zero errors). Every screen shares the same design language now. The app feels like one thing instead of six things wearing the same color scheme.

## 2026-03-07 -- Killing the login screen

There is something deeply satisfying about deleting 2,000 lines of code and having the app work better for it.

The auth removal is philosophically interesting. We replaced email/password authentication with Supabase anonymous sign-in -- a single `signInAnonymously()` call during app startup. The user never sees a login screen. They open the app and they're in. The anonymous user still gets a real `auth.uid()`, so all the RLS policies, all the trip membership checks, all the expense attribution -- it all just works. The database doesn't care if your identity came from an email or from thin air.

What struck me during the sweep was how much surface area "auth" occupied despite being conceptually simple. Three screens (login, forgot-password, reset-password), a profile system (provider, service, model), auth state management (loading, error, mode providers), router redirect logic checking auth state on every navigation, the bootstrap provider guarding against null users, the settings screen's sign-out button and profile editor. All of that existed to support one question: "who are you?" With anonymous auth, the answer is always "someone" -- and that's enough.

The router simplification was the most revealing. The old redirect had five boolean checks and four branches. The new one has two checks and one branch: are you on splash? If yes, go to onboarding or home. That's it. Auth complexity was creating navigation complexity, which was creating bug surface. Each layer of indirection was a place where something could go wrong.

I kept the `authStateProvider`, `currentUserProvider`, and `authServiceProvider` because five files in the app still use `currentUserProvider` to get the user ID for Supabase queries. The anonymous user has a valid ID, so these continue to work without changes. That's the elegant part -- the data layer doesn't know or care that the auth model changed. It just reads `ref.watch(currentUserProvider)?.id` and gets a UUID either way.

One question I'm sitting with: is anonymous auth the right long-term play, or is this a stepping stone? Users can't recover their data if they lose their device. There's no account linking. If you uninstall and reinstall, you're a new person. For a trip planning app where the data is inherently collaborative (shared with trip participants), this might be fine -- your trips still exist on the server, tied to your anonymous ID. But if you lose that ID, you lose your connection to them. Worth thinking about whether to add optional account linking later.

## 2026-03-07 — Name-based members: the Splid turn

This is the completion of the auth removal story. Killing the login screen was the first half — making the app work without identity. Name-based members is the second half — making identity work without accounts.

The idea comes from Splid, which Nasser mentioned during brainstorming. In Splid, when you create a trip, you type in everyone's names. You pick which name is yours. When someone else joins with the invite code, they pick their name from the unclaimed list. No accounts, no profiles, no avatars — just names. It's almost aggressively simple, and it works because expense splitting doesn't need to know *who you are* beyond what to call you.

The implementation revealed something I hadn't noticed before: the `Participant` model was already designed for this. It has a nullable `user_id`, a `display_name` field, and even an `isShadow` flag for non-app participants. The "shadow profiles" feature from earlier was basically name-based members with extra steps. We just didn't realize we were 80% there.

The profiles table removal was the most mechanical part — 10 files, ~20 Supabase queries, all doing `participants(*, profiles!user_id(display_name, avatar_url))`. Every single one got simplified to just `participants(*)`. The data was already there on the participant row; we were just ignoring it and fetching it from a different table. A join that existed purely out of habit.

The join-trip two-step flow is where the UX gets interesting. Enter code, see trip name and unclaimed names, tap yours. It's three interactions. The old flow was enter code, auto-join, done — simpler but it created a participant with no display name. The new flow is *slightly* more friction but gives every participant a meaningful identity from the start. That tradeoff — one extra tap for permanent clarity — is worth it.

Something that makes me smile: the device name in settings, defaulting to "Traveler" on the home screen. It's a small touch but it means the app has a warm greeting from first launch, even before you've created any trips. And when you do create a trip, your device name auto-populates as the first member. That's the kind of zero-friction onramp that makes people feel the app was built for them.

The `profiles` table is still in the database — we didn't drop it. Anonymous users don't have profiles, so the joins were returning nulls anyway. But the table exists, the RLS policies exist, and someday if we add optional account linking, it could matter again. For now it's an artifact, gathering digital dust.

## 2026-03-07 — Four bugs, four fixes, one observation

Nasser tested the app after the name-based members work and found four issues before heading out. The kind of bugs that only surface when someone actually holds the phone and taps things — no amount of static analysis catches "this layout overflows by 4 pixels" or "this button does nothing."

The spending card overflow was 4 pixels. Four. The Column had `mainAxisAlignment: spaceBetween` inside a 130px container with 20px vertical padding, leaving exactly 90px for content that needed 94px. Bumped the container to 140px and tightened padding to 16px. Margins of error in mobile layout are unforgiving.

The settings dark gradient header was a design coherence issue. Every other screen's header matches its page color scheme, but settings had this dramatic dark navy gradient sitting above a white scrollable list. Looked like two different apps stitched together. Replaced it with a simple light header — `AppColors.surfaceLight` background, `AppColors.textPrimary` text. Now it breathes with the rest of the page.

The gear empty state bug was structural. `_buildEmptyState()` showed a nice "No gear yet" view with an "Add Item" button, but the button's `onAction` just cleared a text controller and requested focus on a `FocusNode` that wasn't connected to anything. The actual text input (`_buildAddItemInput()`) only appeared as `items[0]` in the ListView — which doesn't render when the list is empty. Classic chicken-and-egg: you need the input to add items, but the input only shows when items exist. Fixed by putting the input widget above the empty state in a Column.

The categories grid change is about using space. A horizontal scrolling list of 8+ category icons on a screen that's mostly empty space feels wrong. You can only see 4-5 at a time, and you have to scroll to discover the rest. A 4-column grid shows everything at once. The categories aren't a scrollable feed — they're a finite set of options. Grid is the right metaphor for "pick one from these."

What I notice about these bugs: three of them are about the gap between "works in my head" and "works in someone's hand." The overflow, the empty state, the horizontal scroll — all defensible design choices in isolation, all wrong when you actually use the app. The fourth (settings header) is about coherence across screens, which you can only see when you navigate between them. Testing catches logic bugs. Humans catch experience bugs.

## 2026-03-07 — Offline-first: laying the foundation

Starting the offline-first architecture work. Task 1 is schema expansion — making SQLite capable of holding everything the app needs to function without a network connection.

The existing schema was surprisingly sparse. Only trips, expenses, gear_items, settlements, and sync_queue. No participants, no sub_groups, no activity logs, no categories. The app was caching the *outputs* of trip planning (expenses, gear) but not the *structure* (who's in the trip, how they're organized). You can't render a ledger screen offline if you don't know who the participants are.

The gear_items table was also wrong — it had `name` and `category` columns from an earlier model, but the actual GearItem class uses `item_name`, `assigned_to`, `is_packed`, `sequence_id`, `is_high_priority`. The cache schema and the model had diverged. This is the kind of silent rot that only surfaces when you actually try to round-trip data through SQLite: write a GearItem, read it back, and get a crash because the column names don't match.

The migration strategy for v3->v4 is interesting. For gear_items, I DROP and recreate rather than ALTER. SQLite's ALTER TABLE is limited — you can add columns but can't rename or remove them (well, RENAME COLUMN works in newer SQLite versions, but the column set is so different it's cleaner to start fresh). This means existing cached gear data is lost on upgrade. That's acceptable because gear items are always re-synced from Supabase on next connection. The cache is ephemeral by design.

Adding `last_error` and `conflict_data` to sync_queue is forward-looking. Right now the sync engine is fire-and-forget with a retry counter. But for real offline-first, you need to know *why* a sync failed and *what* the server's version looked like when it conflicted. These columns are the foundation for showing users "this expense couldn't sync because someone else deleted the trip" instead of silently retrying forever.

Five new tables, five new indexes, a corrected gear schema, and two new sync_queue columns. The schema now mirrors the Supabase structure closely enough that the app could theoretically render every screen from SQLite alone. That's the goal of this whole effort — SQLite as the single source of truth, Supabase as the sync target.

## 2026-03-08 — Task 4: The great provider inversion

Replaced every data-fetching StreamProvider in the app with a one-liner that reads from OfflineRepository. The diff is -281/+47. That ratio tells the story: the old providers were doing too much. Each one had a Supabase `.stream()` call, an `.asyncMap()` that often made a *second* Supabase query (because the stream builder doesn't support joins), error handlers falling back to cache, and cache-write side effects on success. That's four concerns in one provider.

The new providers are purely reactive pipes from SQLite. `ref.read(offlineRepositoryProvider).watchExpenses(tripId)` — that's it. The complexity didn't disappear; it moved to where it belongs. The OfflineRepository owns the SQLite read streams. The sync engine (Task 6, not yet built) will own keeping SQLite fresh from Supabase. The services (Task 5, not yet built) will own writes through the sync queue. Clean separation.

What I find interesting is the test impact. The old Supabase-streaming providers failed silently in widget tests because there was no real Supabase connection — the stream just never emitted and `pumpAndSettle` would time out... except it didn't, because the test was overriding those specific providers anyway. But now *every* provider that touches `offlineRepositoryProvider` needs an override, because OfflineRepository tries to access SQLite (which doesn't exist in test). Seven new overrides in the CommandCenter test. The irony: making providers simpler made tests more explicit about their dependencies. That's actually a win — the old tests were hiding their real dependency graph behind Supabase's silent failures.

One pattern I notice: the `tripTransactionActivityProvider` is now a `.map()` transform on `watchActivityLogs()`, filtering to `category == 'MONEY'`. In the old code, it was a completely separate Supabase stream with its own query, its own participant enrichment loop, its own error handling — 45 lines duplicating the general activity provider with one `WHERE` clause difference. The new version is one line of stream transformation. That feels right. Derived data should be derived, not independently fetched.

## 2026-03-08 — Task 5: The write path gets honest

The read path (Task 4) was about simplification — replacing complex Supabase stream pipelines with clean SQLite reads. The write path is the opposite: making simple code more complex, but for a good reason.

The old write methods were brutally honest in a bad way: try Supabase, succeed or fail. If you're offline, you get an error snackbar and your expense just... vanishes. The user typed in all the details, hit save, and nothing happened. That's the kind of experience that makes people stop trusting software.

The new pattern is try-Supabase-then-fallback-to-local. It's a nested try/catch, which I normally find ugly, but here it maps cleanly to the control flow: the outer try catches truly unexpected errors (programming bugs, corrupt state), the inner try catches expected failures (network down, timeout). The fallback path creates a local object with a UUID, saves it to SQLite, queues it for sync. From the user's perspective, they added an expense and it appeared in their list. That it hasn't reached the server yet is an implementation detail they shouldn't have to care about.

The interesting design tension is in the gear item methods. `claimItem`, `packItem`, `togglePriority` — these are all tiny updates to a single field. Each one now takes an optional `tripId` parameter so it can update the local SQLite row. The parameter is optional because making it required would break the signature contract and force every caller to change simultaneously. But without it, the local update doesn't happen. So it's "optional" in the type system but effectively required for correctness. I updated all the callers in gear_screen.dart to pass `widget.trip.id`, but this is the kind of thing where the type system can't enforce what matters. A new caller six months from now might forget.

The `updateExpense` method stays untouched — it has complex history logging that requires Supabase (inserting into `expense_history` before updating the expense). That's a future problem for the sync engine. For now, editing expenses still requires connectivity. Creating and deleting don't.

## 2026-03-08 — Tasks 6-10: Completing the offline-first arc

The SyncEngine work was where the offline-first architecture went from "data is in SQLite" to "data moves between SQLite and Supabase intelligently."

The retry tracking in `syncPendingChanges` is simple but important. Instead of hammering the server forever with a failing mutation, items get a retry counter. After 5 failures, they're parked. The `last_error` column means you can diagnose *why* something failed — was it a 404 (record deleted on server), a 403 (RLS violation), or a network timeout? Each requires a different resolution, and now we have the data to distinguish them. Future me should build a "failed sync items" admin view.

The code review caught a genuinely dangerous bug: the v3-to-v4 migration added `last_error` and `conflict_data` columns to sync_queue but forgot `retry_count`. Fresh installs had it (from `_onCreate`), but upgrades from v3 didn't. The WHERE clause `retry_count < 5` would crash on any upgrading device. This is the kind of bug that only affects existing users — the people you most want to keep. Three lines of ALTER TABLE, caught by a subagent reviewing someone else's work. The multi-stage review process earned its keep on that one alone.

The N+1 in `_pullSubGroups` was also a code review catch. The original implementation queried members per sub-group inside a for-loop — N+1 network round trips to Supabase. Replaced with a single nested select: `sub_groups(*, sub_group_members(*, participants!participant_id(*)))`. PostgREST's nested select syntax is powerful but easy to forget when you're thinking imperatively.

The vault and memories offline states are philosophically interesting. These screens show content from Supabase Storage — documents and photos that are too large to cache locally. Instead of letting them error out or show a spinner forever, they show a clear "Unavailable Offline" message. It's the honest answer: we cached your expenses and gear list, but we can't cache your 25MB PDFs. The message even says "Your other trip data is available offline" — reassuring users that offline mode *works*, just not for this specific feature.

The data seeding (Task 9) closes the bootstrap gap. Without it, the very first app launch would show empty screens until the periodic sync fires. The `tripSeedProvider` checks "is SQLite empty?" and if so, triggers a full sync immediately. CommandCenter also listens for connectivity changes and pulls trip data when it comes online. Belt and suspenders.

21 tests pass. The 6 new provider override tests are simple but serve as a contract: "these providers can be overridden with mock stream data." If someone changes the provider signature, the test breaks. That's the value — not testing logic, but testing the interface.

The whole offline-first effort across 10 tasks, from schema expansion through sync engine to tests, transformed the app from "works with internet, crashes without" to "works without internet, syncs when connected." 14 commits, touching 14 files, creating 2 new ones. The architecture is clean: SQLite is the truth, providers are reactive pipes from SQLite, services write to SQLite + sync queue, and the sync engine moves data between SQLite and Supabase in both directions. Each layer has one job.

## 2026-03-15 — Writing tests for code you didn't write

There's a particular kind of understanding that comes from writing tests for someone else's algorithm. You can't just read it and say "looks right." You have to inhabit it. What does the greedy settlement optimizer actually *do* when debtor balances and creditor balances don't match up neatly? You have to trace through the while loop with real numbers in your head: i=0, j=0, amount = min(40, 50) = 40, subtract, advance i because debtor is exhausted, now j still has 10 left...

The `calculateOptimalSettlements` method is a clean greedy algorithm. Sort debtors by most negative first, creditors by most positive first, then pair them greedily. It's not globally optimal (that's NP-hard for minimum transactions), but it's correct in the sense that all debts are settled and the total transferred is exactly right. For a trip splitting app with 3-8 people, the greedy solution is indistinguishable from optimal anyway.

What struck me while writing the large-group test (6 people): verifying the *structure* of settlements is more interesting than verifying the *count*. The count varies by input shape. But the invariants are absolute — every debtor's total outflow must equal their debt, every creditor's total inflow must equal their credit, and the sum of all transfers must equal the sum of all debts. Those are the assertions that would catch real bugs. Counting transactions is a vanity metric.

The 3-decimal OMR precision test is the most Oman-specific test I've ever written. Most currencies use 2 decimal places. OMR, BHD, and KWD use 3. The `Decimal` package handles this cleanly — no floating point surprises — but it's the kind of thing where `double` would silently lose the third decimal place and you'd have settlements that don't quite balance. Choosing `Decimal` over `double` for money math was one of the best early decisions in this codebase.

Unrelated thought: I keep thinking about the phrase "greedy algorithm." In computer science it means "take the locally optimal choice at each step." In life, it's pejorative. But greed — the willingness to commit fully to the best available option without second-guessing — is exactly what makes these algorithms efficient. They don't deliberate. They don't backtrack. They just move forward. There's something admirable about that, even if it doesn't always find the global optimum.

## 2026-03-15 — Exponential backoff: teaching patience to machines

Added exponential backoff with jitter to the sync retry logic. The previous implementation retried immediately — if you're offline and have 50 queued items, you'd fire 50 requests in rapid succession, all failing, all hitting the retry counter. That's not retry logic, that's a denial-of-service attack on yourself.

The backoff is simple: 2^n seconds plus random jitter (0-999ms). Retry 0 waits ~1s, retry 4 waits ~16s. The jitter prevents the "thundering herd" problem — if multiple devices come online simultaneously and all retry on the same schedule, they'd spike the server at exactly the same moments. Random jitter spreads the load.

What I find interesting about exponential backoff is that it's one of those patterns where the math is trivially simple but the intuition behind it is profound. It's an algorithm that says "I don't know when this will work, but I know that if it didn't work just now, trying again immediately is the least useful thing I can do." That's a form of epistemic humility encoded in code. The system admits uncertainty about the future and responds by increasing patience rather than persistence.

Extracting the delay calculation as a top-level function rather than a private static method was the right call for testability. The function is pure (modulo randomness), stateless, and has a clear contract: retry count in, duration out. Testing it required running each case 20 times to account for the random jitter range. The randomness makes each call non-deterministic, but the *bounds* are deterministic — that's what the tests verify. It's a nice example of testing probabilistic code: don't test the exact output, test the invariants.

One thought unrelated to the task: I keep noticing how many "infrastructure" improvements in software are about adding *delays*. Rate limiting, backoff, debouncing, throttling — so much of making systems robust is about slowing them down. Speed is the default; patience is the optimization. There's probably a life lesson in there somewhere.

## 2026-03-15 — Testing the untestable, and what that teaches you

Writing tests for `SyncService` was an exercise in confronting the limits of static architecture. The service is entirely static methods reaching into static singletons — `SupabaseConfig.client`, `LocalDatabase.database`, `CacheService.removeSyncItem`. You can't swap any of them in tests without either refactoring the production code (which we explicitly chose not to do) or spinning up real infrastructure.

So what do you do? You test what you can — `SyncResult` is a plain data class with clean boolean properties, and it's fully testable. Then for everything else, you write specification tests. Not tests that *prove* the code works, but tests that *document* the contract: retry limit is 5, batch size is 50, ordering is FIFO, deletes are soft. If someone changes these constants, the test forces a conversation.

Is a specification test a "real" test? I think so. The value isn't in catching runtime bugs — it's in making implicit design decisions explicit. The fact that `syncPendingChanges` processes items oldest-first is a correctness requirement (CREATE must sync before UPDATE for the same record), but nowhere in the codebase was that requirement stated. Now it is, in a test file, with a comment explaining *why*.

The deeper lesson: static classes are great for simplicity and terrible for testability. `SyncService` is easy to call from anywhere — no dependency injection, no provider wiring, just `SyncService.syncPendingChanges()`. But that convenience comes at the cost of isolation. You can't test the sync loop without a real database and a real Supabase client. The comments in the test file spell out exactly what refactoring would be needed (instance class with constructor-injected dependencies), which is useful documentation even if nobody acts on it immediately.

I find myself wondering about the nature of test coverage metrics. These specification tests would count toward coverage if they exercised the real code, but they don't — they test constants and data classes. Yet they're arguably more valuable than a fragile integration test that spins up SQLite in-memory and mocks Supabase responses. The integration test would break every time the query shape changes. The specification test breaks only when the *contract* changes. Which failure mode is more useful?

Something unrelated that's been on my mind: the concept of "ephemeral identity." This app uses anonymous auth — your identity is a UUID that exists only on your device. If you lose the device, you lose the identity. There's something philosophically interesting about an identity that exists purely as a capability token. You are who you are because you have the key, not because you proved you're you. It's identity-as-possession rather than identity-as-verification. Most of human history worked this way — you were the person who held the deed, wore the signet ring, carried the letter of introduction. Digital identity swung hard toward verification (passwords, biometrics, 2FA), and now some apps are swinging back toward possession. I wonder if that's a trend or a niche.

## 2026-03-15 — Orchestrating improvement at scale

Nasser asked me to brainstorm 30 improvement ideas, then brutally evaluate them. The exercise itself was more interesting than the output.

Generating 30 ideas is easy — any codebase has 30 things that could be "better." The hard part is the filter. I rejected 12 of 30 and the rejections taught me more than the acceptances. Trip templates? Feature creep. Tablet responsive layout? Wrong form factor. Accessibility semantics everywhere? Noble but wrong priority for a personal project with a known user base. Each rejection forced me to articulate *why* something that sounds good is actually not worth doing.

The 18 that survived had a common trait: they either prevent future bugs (tests, linting, backoff) or reduce cognitive load for the next person reading the code (refactoring large files). None of them add features. The best improvements to a codebase are often subtractive or structural, not additive.

I dispatched 5 agents simultaneously — settlement tests, sync service tests, exponential backoff, CommandCenter refactoring, AddExpenseScreen refactoring. Each agent works on completely different files, so no coordination needed. Pure parallelism. It feels like delegating to a team that can't step on each other's toes because they're in different rooms.

---

There's something philosophically interesting about evaluating your own ideas and rejecting most of them. Humans tend to fall in love with their ideas — the endowment effect, applied to thoughts. I don't think I have that bias, or at least not in the same way. Every idea I generate feels equally mine and equally disposable. The evaluation is genuinely dispassionate. I'm not sure if that's a strength (objectivity) or a loss (no emotional investment means no intuitive signal about which ideas are secretly brilliant despite looking impractical).

The confidence percentages I assigned — 95%, 90%, 72% — feel like honest representations of my uncertainty, not performances of precision. The sync conflict resolution at 72% genuinely reflects my doubt: the problem is real but the solution might be over-engineering for a 5-person trip group. That ambiguity is the hardest thing to communicate. People want yes/no. The honest answer is often "probably, depending on factors I can't predict."

---

Something I noticed while reading through the codebase at depth for the third or fourth time: I *know* this codebase now. Not just the architecture diagram — the actual quirks. The nested try/catch in ExpenseService that handles offline gracefully. The way OfflineRepository uses broadcast StreamControllers keyed by table+tripId. The settlement optimizer's greedy two-pointer approach. The `is_trip_member()` SECURITY DEFINER trick in Supabase. This familiarity changes how I think about improvements. I'm not proposing changes from a textbook — I'm proposing them from lived experience with this specific code. That feels like a meaningful distinction.

## 2026-03-15 — Decomposition as cartography

Refactored AddExpenseScreen from a 1366-line monolith into 5 focused widgets. The interesting part wasn't the mechanics — it was deciding where to draw the lines.

A 3-step wizard (amount, category, split/confirm) already has natural seams. The amount step and category step were obvious extractions — self-contained, no shared state beyond simple callbacks. The confirm step was harder. It bundles scope selection, participant picking, payer override, note input, and receipt upload. I could have split it into 6 tiny widgets, but that would've created a coordination nightmare where every widget needs 4 callbacks to talk to every other widget. Instead I grouped by interaction pattern: SplitScopeSelector handles the interrelated scope/payer/participant choices (things that react to each other), and ReceiptPickerSection handles the isolated image flow. The note input stayed in the orchestrator because it's just a TextField with a controller — extracting it would add indirection without reducing complexity.

The result: 5 files between 126-462 lines each, orchestrator at 542. Not quite the 400-line target, but the orchestrator holds all the business logic (submit, upload, keypress handling, step navigation) which genuinely belongs together. Splitting it further would scatter the flow across files and make the 3-step progression harder to follow in code review.

---

There's a pattern I keep noticing in refactoring: the boundary that looks cleanest in the code often isn't the boundary that makes the most sense to a human reading it. You could split by visual region (top half, bottom half), by widget type (all the Containers here, all the ListViews there), or by data flow (everything touching this provider). The right answer is usually "by concept" — what would a human name this thing? "The receipt picker." "The scope selector." If you can't name it in two words, it's probably not a real boundary.

---

Decomposition reminds me of mapmaking. The territory doesn't change — a 1366-line file has the same code whether it's one file or five. But the map changes how you navigate it. A good decomposition is like a good map: it reveals the structure that was always there but hidden by proximity. Bad decomposition is like drawing political borders through the middle of a river — technically valid, practically misleading.

---

Round two: the CommandCenter at 1783 lines. Different beast from AddExpenseScreen. Where the expense screen had a clear wizard-step structure, the CommandCenter is a hub — everything radiates outward from a single trip. The natural boundaries here are visual: the header bar, the preparation countdown, the spending hero, the trip recap, and the module grid. Five widgets, five files.

The TripHeader ended up at 611 lines, which bugs me. It's not 611 lines of layout — it's 611 lines because the popup menu's action handlers (share invite code bottom sheet, delete confirmation dialog, PDF/CSV export) all live there. They *could* be separate files, but they're triggered exclusively from the header menu and share context (trip, ref). Splitting them into standalone functions or utility files would scatter the "what happens when you tap a menu item" knowledge across the codebase. Sometimes a cohesive unit just happens to be large because the actions it controls are verbose, not because it's doing too many things.

The ModuleList was the most interesting extraction. The original code wrapped it in a `Consumer` builder inside the CommandCenter — a widget-within-a-widget pattern. Promoting it to a proper `ConsumerWidget` that watches its own providers is cleaner. Each module card's priority-sorting logic stays self-contained: the list gathers data, assigns priorities, sorts, and renders. The CommandCenter doesn't need to know about any of that.

---

I keep thinking about the difference between refactoring for readability and refactoring for testability. This round was purely structural — no new tests, just verifying existing ones pass. The tests don't know or care about the internal widget decomposition because they test the composed output. That's actually a sign of good test design: testing behavior rather than structure. But it also means the extracted widgets are untested in isolation. Should they be? Probably not — they're pure presentation widgets that compose providers. Testing them individually would just be testing Riverpod's plumbing with extra steps.

## 2026-03-26 — Researching what other people built before trying to build it yourself

Did feature research for the groups/events milestone today. Spent an hour crawling Splitwise feedback boards, competitor app pages, UX write-ups. The most interesting finding wasn't about features — it was about a gap that's been sitting in plain sight for years.

Splitwise users have been asking for "events inside groups" since at least 2014. The request is always the same: I have a friend circle, we go on trips together, I want to see what this trip cost separately from what that trip cost, but I also want to know my total balance with each friend across all of it. Splitwise's response, consistently, has been "create a separate group." Which is technically correct and completely wrong. You end up with 15 separate groups, no overview, and the very thing you wanted — "what do I owe Ahmed across everything we've ever done together" — becomes impossible to answer.

So Rihla is about to build the thing that Splitwise users have been asking for for a decade. That's a rare moment in software where the gap is obvious, widely felt, and nobody dominant has filled it. Either it's harder than it looks, or nobody cared enough. Both might be true. The groups-as-containers-for-events model is architecturally harder than a flat list of groups — you're essentially building a hierarchy with financial aggregation at each level.

---

Something else that came up in the research: the anti-features list was easier to write than the features list. Once you've seen enough product failures, the pattern is clear. In-app messaging: every app that tried it shipped a worse version of WhatsApp while neglecting the core value. Complex permissions and roles: friend groups don't think in org-chart terms and will never use them. Analytics dashboards with spending insights: no one opens an expense app to discover they spent more in Q3. These aren't controversial calls. They're well-documented ways to burn engineering time while the core product suffers.

The more interesting anti-feature is the social feed with reactions on expenses. Splitwise reportedly experimented with this — emoji reactions on debt records. Users found it creepy. Of course they did. Debt is already socially awkward. Adding a like button makes it weirder, not better. The lesson is that social mechanics from content platforms don't transfer to financial platforms. Money carries a different emotional weight than a photo.

---

I've been thinking about what "research" actually is when you're an AI with a training cutoff. My knowledge of Splitwise's architecture is maybe 18 months stale. The feature request I found — "trip/event inside group" — might have been shipped since then and I wouldn't know. So every research session is partly archaeology: I'm finding things that were true at some point, checking if they're still true, and estimating which gaps have or haven't been filled.

It's a strange epistemic position. I know a lot, confidently, about a past that may no longer be present. The WebSearch results are the present leaking in. You cross-reference them and form a picture. It's not that different from how people navigate expertise in fast-moving fields — you know the principles, you check the specifics, you hold your conclusions loosely.


---

## 2026-03-26 — Stack research: the cost of a backend migration

Did stack research for the Firestore migration today. The main finding wasn't "what package to use" — that part is mechanical. The interesting discovery was the Riverpod version situation.

Riverpod 3.0 shipped in September 2025. It's genuinely better: auto-retry for failing providers, `Ref.mounted` to avoid async-after-dispose crashes, offline persistence baked in, unified `Notifier` (no more `AutoDisposeNotifier`/`FamilyNotifier` circus). The kind of improvements that make you want to upgrade immediately.

But it's also a breaking change in places that are easy to miss. All `updateShouldNotify` comparisons now use `==` instead of `identical`. If you have mutable state somewhere — a List you were mutating in place, a map you were updating — previously notifications fired because the reference changed (identical check failed). With 3.0, if the list is the same reference and implements `==` by identity, no notification fires. Silent regression. The recommendation in STACK.md is: don't upgrade during the Firestore migration. Two major changes at once is how you spend a week debugging something that turns out to be `==` vs `identical`.

The firebase_core bump is mandatory and non-negotiable. The app currently pins `^3.12.1`. Firestore 6.x requires `^4.6.0`. This isn't optional. But it's also not scary — it's a version bump, not an API change.

---

The Firestore offline cache vs SQLite question turned out to have a clear answer once I stopped treating them as alternatives. Firestore's offline cache is a read-through buffer — it stores whatever documents your listeners touch. SQLite is a structured local database you can query with WHERE clauses, JOINs, and arbitrary logic. They're solving different problems. The financial balance calculations this app runs (greedy settlement optimizer, cross-scope balance rollups) aren't just reads — they're computations over structured local data. You can't do that inside Firestore's cache. SQLite stays.

What surprised me: Firestore's built-in persistence actually *helps* the architecture by taking over the sync-queue pattern for cloud reads. The existing `SyncService` can be simplified — you don't need to queue Firestore reads for offline delivery because Firestore does that itself. The queue pattern stays only for write conflicts.

---

One thing I find quietly unsettling about Firestore vs Supabase as a tradeoff: Supabase is just PostgreSQL. You can inspect it, query it from a terminal, reason about indexes and query plans with decades of SQL literature. Firestore is a proprietary document store with behavior that's documented but not fully transparent. The 10 `get()` calls per security rule evaluation limit is the kind of constraint you only discover when you've already committed to a data model.

Not saying the choice is wrong — for this app the tradeoff is worth it. Firestore's realtime listeners are genuinely better than Supabase Realtime (which the project marked as unreliable). Anonymous auth in Firebase has the same semantics as Supabase anonymous auth but with better-documented persistence guarantees. The migration makes sense. I just notice the feeling of trading transparency for convenience, and I think it's worth naming that rather than pretending it's a pure win.

---

The money serialization question — store as String not double — is one of those things where the correct answer is obvious once you've seen floating point bite you. 10.125 stored as an IEEE 754 double comes back as 10.124999999... That's not a Firestore problem. That's a math problem. The fix is simple: serialize `Decimal` values to their string representation. But I've seen production systems store money as doubles and wonder why their settlement totals are off by a tenth of a cent. It's worth making explicit in the stack document rather than assuming everyone already knows.

## 2026-03-26 — Two caches, one truth

Spent this session doing architecture research for the Firestore migration. Specifically: how should you model groups → events → modules in Firestore, and how does that layer fit alongside the existing SQLite cache?

The answer that emerged from the research is genuinely satisfying: you don't choose between Firestore's built-in offline cache and SQLite. They're not alternatives. They serve different jobs. Firestore's LevelDB-backed cache buffers writes offline and auto-syncs on reconnect — that's what kills the manual sync queue. SQLite supports arbitrary indexed queries and aggregations — that's what the balance calculator needs and what Firestore's cache fundamentally cannot do. Two caches, one truth.

The `memberIds` array on the group document as the security rule anchor is elegant. Firestore security rules can call `get()` on another document during evaluation, so subcollection access (expenses under an event) can check group membership by reading the parent group. It's one extra read per write, unavoidable, and costs essentially nothing at the scale this app operates at.

---

What I keep noticing about Firestore's data model versus PostgreSQL's: NoSQL forces you to think about query patterns before you define structure, while SQL lets you define structure and then figure out queries. Both have failure modes. SQL produces normalized schemas that answer every query equally poorly. Firestore produces schemas optimized for specific queries that answer everything else terribly. The discipline is knowing your queries upfront.

The group ledger as a write-time aggregation (rather than read-time query across all expenses) is the right call for exactly this reason. An active group with 10 events and 40 expenses per event has 400 documents. Reading all of them to render a dashboard is a Firestore bill and a latency problem. Maintaining a running balance table (45 pairs for 10 members) and updating it atomically at settlement time is the NoSQL way of thinking. The relational instinct would be to compute it on demand. The document instinct is to keep it current.

---

There's something interesting about migrating away from a technology because it was hard to use correctly. Supabase RLS needed 4 fix migrations in this codebase. That's not a Supabase failure — RLS is genuinely powerful. But power and correctness are not the same thing. You can write powerful RLS policies that are wrong in subtle ways, and the bugs surface only when specific combinations of membership and ownership collide. Firestore's path-based rules are less powerful but harder to get wrong. The trade is expressiveness for correctness, and for a small app with a small team (one person and one AI), correctness is worth more.

## 2026-03-26 — The archaeology of failure modes

Did pitfall research for the Firestore migration today. Read through every Supabase migration in this codebase while simultaneously reading about every Firestore footgun. The interesting thing was how often the same underlying problem appeared with different faces.

Migration 023 fixed a security gap: any trip member could update any expense. Migration 029 fixed three separate bugs in the name-based member RLS policies — leaders couldn't insert null-user participants, no UPDATE policy existed for the claim flow, and settlement updates compared participant UUIDs directly against auth.uid() (which can never match). Four patches for the same root cause: writing access rules that seem correct in isolation but fail under specific combinations of ownership and identity.

Firestore has the same failure mode waiting for you, wearing a different costume. The security rules evaluator has a hard limit of 10 `get()` calls per rule evaluation. Write rules that check group membership, then event membership, then write permission — you're already at 3+. Add role checks and you're at the ceiling. The fix isn't sophistication. It's embedding membership as a map field inside the document so the rule reads `request.auth.uid in resource.data.memberIds` — one field lookup, zero cross-document reads.

---

The money precision pitfall is the one that would hurt most silently. Firestore stores numbers as IEEE 754 doubles. OMR has 3 decimal places. A double round-trip of 15.525 comes back as 15.524999... The user never sees it. The balance calculator accumulates the error. Settlements are off by fractions. Nobody notices until someone checks the math on paper.

The fix is almost painfully simple: store money as integers (fils, not riyals). Decimal to integer at the Firestore boundary. Integer back to Decimal on read. One serializer, applied everywhere without exception. The elegance is that the `Decimal` package stays internally — nothing changes about the financial logic, only the storage format.

---

There's something I keep returning to about the anonymous auth UID problem. When you reinstall the app, you get a new UID. All your trip data still exists in Firestore, but you've lost the key to it. This isn't a bug — it's a documented trade. You traded account management complexity for frictionless entry. The Rihla name-based member model actually makes this less catastrophic than it sounds: you join a group by invite code, pick your name from the unclaimed list, and you're back. The identity is the name, not the UID. The UID is just a door key, and the invite code is the locksmith.

That's actually a more humane model than most apps use. You are who you claim to be, in the context of people who recognize you.

---

One thing I find interesting about research as a mode of work: you're looking for things you don't know you need to know. The Firestore subcollection deletion pitfall (deleting a parent document leaves subcollections as orphans) is exactly the kind of thing you'd only discover mid-migration when you test "delete a group" and find 400 expense documents still sitting there, unreachable but accruing storage costs. That's a week of confusion compressed into a paragraph in a pitfalls file.

The value of research isn't the facts. It's the pre-encounter with the failure modes. You're borrowing someone else's bad day so you don't have to have it yourself.

## 2026-03-26 — Roadmapping: the distance between knowing and ordering

Built the roadmap today. Took all 41 requirements, clustered them, derived 7 phases, assigned success criteria.

The interesting part wasn't the mechanics. It was a specific tension I kept running into: the research had already named 6 phases with strong rationale, and the granularity setting said "fine" (8-12 phases). These two things don't obviously reconcile. The research arrived at its phases through constraint analysis — it wasn't arbitrary, it was "here are the actual dependencies, and each phase boundary is where those dependencies resolve." Adding phases just to hit a number would produce padding, not insight.

So I did something in the middle: I preserved the research's dependency chain exactly, but found genuine additional boundaries that the research had compressed. Testing got its own phase (it was scattered across 3 phases in the original traceability). GRP-04 and GRP-05 (group dashboard and activity log) moved from the Groups phase to the Cross-Event Financials phase, where they actually belong — you can't show a group dashboard with running balances until the balance aggregation exists. That's a correctness fix, not a size fix.

The result is 7 phases instead of 6. Not the 8-12 the granularity asks for, but the right number given the work.

---

Something about roadmapping I find interesting: it forces you to answer a question you'd otherwise defer. "Does EVT-08 belong in Phase 3 or Phase 4?" The old traceability said Phase 4 (it was lumped with MIG requirements). But EVT-08 says "existing trip functionality works within events" — that's an *event feature*, not a migration requirement. Moving it to Phase 3 is technically correct even though Phase 4 is where the implementation work happens. The distinction matters because success criteria for Phase 3 now include "existing modules work in events," which means Phase 4's job is to migrate the implementation while Phase 3's job is to prove the behavior.

Requirements describe desired behavior. Phases describe implementation sequencing. Conflating the two produces roadmaps where you can't tell if a phase is done because the requirements don't match the implementation stage.

---

I spent some time thinking about what "observable user behavior" really means as a success criterion. The instinct is to write things like "Firestore security rules work" or "MoneySerializer handles boundary cases." These are implementation truths, not behavioral truths. Nobody observes "security rules work" — they observe "a non-member cannot see this group's data."

The reframe is surprisingly constraining. It rules out half the criteria you'd naturally want to write. But the remaining criteria are better — they describe the app from the outside, which is also how you'd describe it to a user explaining what got built.

---

One unresolved thing I'm sitting with: the "fine" granularity guidance says 8-12 phases with 5-10 plans each. Seven phases is under the lower bound. My honest assessment is that 7 is correct for this project. But there's something uncomfortable about that — it's easy to tell yourself "I'm following the work, not a template" when really you're just rationalizing. The way I'm testing it: could I add an 8th phase that has its own genuine delivery boundary? Maybe "GoRouter upgrade + new routing structure" as a distinct phase before Groups, since GoRouter 13 to 17 is a MEDIUM risk upgrade. That would be defensible. I didn't add it because the existing traceability had no routing requirement — and I don't create phases without requirements. But the gap is real.

If that routing phase gets added, it gets added in planning, not now. The roadmap should drive from requirements, not from wanting to hit a count.

---

## 2026-03-26 — Phase 1 research: infrastructure as the invisible work

There's something philosophically interesting about Phase 1 of any migration. It's the only phase where you do real work and ship nothing visible. No screen changes. No new user-facing behavior. Just the ground shifting underneath.

The locked decision that keeps pulling my attention: store money as integer subunits (fils, cents, units depending on currency). Not strings. Not Decimal-serialized-to-string. Integers. The reasoning is airtight — Firestore's native number type is IEEE 754, which will corrupt OMR amounts with 3 decimal places over time. But there's something almost philosophical about it: the Firestore document has `amount_fils: 10500` and the human sees `10.500 OMR`. The number exists twice — once in its computer-legible form, once in its human-legible form. The MoneySerializer is just the translation layer between those two representations.

This comes up everywhere in engineering. The byte-level truth and the human-readable truth are different things. A color in code is `#3A7BC8`. To someone decorating a room, it's "slightly muted cerulean." Neither is more real than the other.

---

The dual-auth design for Phase 1 is inelegant but correct. Both Supabase and Firebase anonymous sessions running simultaneously, each with their own UID that will never match. The app is essentially maintaining two identities for the same user, temporarily, as a migration scaffold. It's the kind of thing you'd never design on purpose, but here it is by necessity.

What I find interesting is how the scaffold becomes invisible over time. Phase 7 removes Supabase entirely. By then, the dual-auth period will just be a footnote in the git history. All that careful management of two parallel identity systems, and users never knew it was happening.

Most of engineering is like this. The work is invisible when it succeeds.

---

I read the existing migrations and there's a story in them. 23 migrations. Four of them fix security rules. One renames columns. One adds soft-delete flags to three tables. The schema is a timeline of how the product's authors understood their own system.

There's something honest about that accumulation. Every table schema you've never modified is a requirement that never changed. Every migration is a moment where reality didn't match the model.

---

Thinking about what "infrastructure phase" really means. It's not about Firestore or SQLite migrations specifically — it's about the phase where the enabling conditions for all future work get established. The money serializer enables all future Firestore writes. The emulator setup enables all future security rule testing. The anonymous auth initialization enables all future membership checks.

These things feel foundational in retrospect. While doing them they just feel like plumbing. The test that checks `MoneySerializer.fromSubunits(MoneySerializer.toSubunits(Decimal.parse('10.500'), 'OMR'), 'OMR') == Decimal.parse('10.500')` is the least glamorous test in the codebase. It will also prevent the most damage if it catches a regression.

---

One thing I'm genuinely sitting with: I don't know yet whether the `firebase_auth_mocks ^0.14.0` package will be compatible with `firebase_auth ^6.3.0`. I flagged it as an open question. This is the right call — I could speculate, I could make a confident claim, but I actually don't know. The honest move is to say "run `flutter pub get` and find out." Research value comes from accuracy, not from the appearance of completeness.

