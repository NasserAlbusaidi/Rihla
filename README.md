# 🌍 Rihla - The Ultimate Group Trip Planner

Rihla (Arabic for "Journey") is a modern, high-performance Flutter mobile application designed to eliminate the friction of planning group trips. From complex expense splitting to collaborative gear lists and logistics management, Rihla keeps everyone in sync and on track.

---

## ✨ Key Features

### 💰 Omni-Splitter (The Ultimate Ledger)
No more awkward spreadsheets. Rihla’s core engine handles complex trip finances effortlessly:
- **Flexible Splitting**: Split equally, by sub-groups (e.g., only those in Car 1), or custom weights.
- **Multi-Currency Support**: Automatic conversion using live rates or manual overrides.
- **Settle Up Engine**: Smart balance calculation that minimizes the number of transactions needed to settle.
- **QR Payments**: Generate payment QR codes for fast, error-free settlements.
- **Audit Trail**: Every change is logged with a transaction timeline.

### 🎒 Smart Gear Tracking
Keep your group prepared with collaborative packing lists:
- **Item Assignment**: Assign gear to specific participants.
- **Real-time Progress**: A "Preparation Meter" on the dashboard shows packing progress.
- **Priority Levels**: Flag essential gear to ensure nothing is left behind.
- **Categorization**: Organize gear by person, category, or sub-group.

### 🚗 Trip Logistics & Sub-Groups
Manage the complex movement of people and equipment:
- **Sub-Group Isolation**: Create sub-groups for different cars, camps, or flight groups.
- **Travel Details**: Store and share flight numbers, hotel bookings, and vehicle assignments.
- **Itinerary Timeline**: A unified view of the trip's schedule and logistics.

### 🔐 Secure Vault
A dedicated space for essential trip documents:
- **Centralized Docs**: Store digital copies of passports, flight tickets, and insurance.
- **Encrypted Storage**: Securely stored using Supabase Storage with strict RLS (Row Level Security) policies.
- **Categorized Access**: Filter by ID, Booking, or Insurance.

### 🔄 Real-time & Offline Ready
- **Instant Sync**: Real-time updates across all devices via Supabase Realtime.
- **Offline Mode**: Full local caching with Sqflite allows you to view and record data even in the middle of a desert.
- **Background Sync**: Automatic queueing of changes for safe synchronization when connectivity returns.

---

## 🚀 Tech Stack & Architecture

Rihla is built with a **Feature-First Architecture** for maximum maintainability:

- **Framework**: Flutter (Current Stable)
- **State Management**: Riverpod 2.x (using Generators)
- **Backend**: Supabase (PostgreSQL, Realtime, Storage, Auth)
- **Local Cache**: Sqflite
- **Navigation**: GoRouter (Type-safe routing + deep links)
- **Animations**: Flutter Animate
- **Error Tracking**: Sentry

---

## 🛠 Getting Started

### Prerequisites
- Flutter SDK 3.10+
- A Supabase Project ([Manual setup required](#1-set-up-supabase))

### 1. Configuration
Rihla uses compile-time variables for security. Create a `config.json` in the root directory:

```json
{
  "SUPABASE_URL": "your-project-url",
  "SUPABASE_ANON_KEY": "your-anon-key",
  "SENTRY_DSN": "your-sentry-dsn"
}
```

### 2. Run the App
```bash
flutter pub get
flutter run --dart-define-from-file=config.json
```

### 3. Database Setup
Migrations are located in `supabase/migrations`. Apply them in numerical order using the Supabase SQL Editor or CLI.

---

## 🧪 Testing & CI/CD
Rihla maintains a rigorous testing standard:
- **Unit Tests**: Core logic and formatting.
- **Widget Tests**: UI component stability.
- **Integration Tests**: Full "Happy Path" E2E flows.
- **CI/CD**: Automatic test execution and release builds via GitHub Actions.

To run tests locally:
```bash
flutter test
```

---

## 📄 License
MIT License - See [LICENSE](LICENSE) file for details.
