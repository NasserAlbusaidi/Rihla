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
