# Creative Overhaul Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform Rihla from a functional group trip app into a delightful, unique experience that attracts and retains users through beautiful onboarding, integrated payments via Thawani, trip photo memories, and warm journey-oriented language.

**Architecture:** Feature-first Flutter with Riverpod. Each new feature gets its own directory under `lib/features/`. Thawani integrates via the existing `thawani_payment` pub package with a custom service wrapper. Onboarding uses SharedPreferences for completion state. Memories uses Supabase Storage with a new `trip-memories` bucket.

**Tech Stack:** Flutter 3.x, Riverpod 2.x, Supabase, thawani_payment package, image_picker (already present), shared_preferences (already present)

---

## Task 1: Thawani Payment Gateway Integration

### 1a: Add thawani_payment dependency

**Files:**
- Modify: `pubspec.yaml` (add thawani_payment: ^1.2.4+1)

### 1b: Create ThawaniService

**Files:**
- Create: `lib/features/ledger/services/thawani_service.dart`

Service wraps Thawani.pay() with app-specific logic:
- Convert OMR amounts to Baisa (x1000) for Thawani's unit_amount
- Map settlement debts to Thawani products
- Handle onPaid callback to mark settlement as paid in Supabase
- Handle onCancelled/onError gracefully

### 1c: Add "Pay with Thawani" to Settle Up screen

**Files:**
- Modify: `lib/features/ledger/screens/settle_up_screen.dart`

Add a prominent "Pay Now" button that triggers Thawani checkout for the selected debt amount.

### 1d: Create Supabase migration for payment tracking

**Files:**
- Create: `supabase/migrations/027_payment_tracking.sql`

Track payment_reference, payment_status on settlements table.

---

## Task 2: Onboarding Experience

### 2a: Create onboarding screen

**Files:**
- Create: `lib/features/onboarding/screens/onboarding_screen.dart`

3 pages with PageView:
1. "Your Journey Begins" - Large illustration area, app name, tagline
2. "Plan Together" - Split expenses, pack gear, share documents
3. "Let's Go" - CTA to get started

Smooth page indicator, skip button, swipe gestures.

### 2b: Wire onboarding into app router

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/main.dart`

Check SharedPreferences for 'onboarding_complete'. If false, route to onboarding before login.

---

## Task 3: Login Screen Refresh

**Files:**
- Modify: `lib/features/auth/screens/login_screen.dart`

Language changes:
- "Tactical Group Expedition Management" -> "Plan journeys together"
- "SECURE ACCESS" / "INITIALIZE ACCOUNT" -> "Welcome back" / "Create account"
- "IDENTIFIER" -> "Email"
- "ACCESS CODE" -> "Password"
- "AUTHORIZE" / "INITIALIZE" -> "Sign In" / "Create Account"
- "RIHLA EXPEDITION SYSTEMS v1.0" -> "Rihla v1.0"
- "ALREADY REGISTERED?" / "NEEDS AUTHENTICATION?" -> softer alternatives

Keep the dark aesthetic and animations - just warm the words.

---

## Task 4: Trip Memories Photo Module

### 4a: Create memory model and provider

**Files:**
- Create: `lib/features/memories/models/memory_model.dart`
- Create: `lib/features/memories/providers/memory_provider.dart`

### 4b: Create memories screen

**Files:**
- Create: `lib/features/memories/screens/memories_screen.dart`

Masonry-style photo grid with date headers. FAB to add photo. Tap to view fullscreen.

### 4c: Create memory service

**Files:**
- Create: `lib/features/memories/services/memory_service.dart`

Upload to Supabase Storage `trip-memories` bucket. Store metadata in `trip_memories` table.

### 4d: Add to CommandCenter

**Files:**
- Modify: `lib/features/home/screens/command_center.dart`

Add Memories module card with camera icon.

### 4e: Supabase migration

**Files:**
- Create: `supabase/migrations/028_trip_memories.sql`

---

## Task 5: Visual Polish

### 5a: Enhanced empty states

Better empty state illustrations using composed widgets (not external assets).

### 5b: Improved transitions

Hero animations between trip cards and command center.

### 5c: Pull-to-refresh

Add RefreshIndicator to home screen and command center.

---

## Execution Order

1 -> 3 -> 2 -> 4 -> 5 (Thawani first since user requested, login refresh is quick win, onboarding next, then memories, polish last)
