# Safar - Trip Planning App

A Flutter mobile app for group trip planning with expense splitting, gear tracking, logistics management, and document sharing.

## 🚀 Getting Started

### Prerequisites

- Flutter SDK 3.10+
- A Supabase account (free tier works)

### 1. Set Up Supabase

1. Go to [supabase.com](https://supabase.com) and create a new project.
2. Wait for the project to be provisioned.
3. Go to **Settings > API** and copy:
   - Project URL
   - `anon` public key

### 2. Configure Environment

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your Supabase credentials:
   ```env
   SUPABASE_URL=https://your-project-id.supabase.co
   SUPABASE_ANON_KEY=your-anon-key-here
   ```

### 3. Set Up Database

1. Go to your Supabase project's **SQL Editor**.
2. Open the `supabase/migrations` folder in this repository.
3. **Important:** You must run the migration files **in order** (from `001` to `020` and any future ones).
   - `001_initial_schema.sql`
   - `002_redesign_schema.sql`
   - ...
   - `020_fix_expense_rls.sql`

   Copy the content of each file and run it in the SQL Editor.

### 4. Enable Authentication

1. Go to **Authentication > Providers**.
2. Enable **Email** provider.
3. Configure:
   - Enable "Confirm email" for production (optional for dev).
   - Set site URL to your app's deep link (for mobile).

### 5. Run the App

```bash
# Get dependencies
flutter pub get

# Run on iOS Simulator
flutter run -d ios

# Run on Android Emulator
flutter run -d android
```

## 📁 Project Structure

```
lib/
├── main.dart                    # App entry point
├── core/
│   ├── config/                  # App configuration
│   ├── providers/               # Global state providers
│   ├── router/                  # GoRouter configuration
│   ├── services/                # Core services (Database, Sync, etc.)
│   └── theme/                   # App theme
├── features/
│   ├── activity/                # Activity logging
│   ├── auth/                    # Authentication
│   ├── gear/                    # Gear tracking
│   ├── home/                    # Command Center / Dashboard
│   ├── ledger/                  # Expense splitting & Settlements
│   ├── logistics/               # Travel logistics
│   ├── settings/                # App settings
│   ├── trip/                    # Trip management
│   └── vault/                   # Document storage
└── shared/
    └── widgets/                 # Reusable UI components
```

## 🛠 Tech Stack

| Category | Technology |
|----------|------------|
| Framework | Flutter 3.10+ |
| State Management | Riverpod |
| Backend | Supabase (PostgreSQL + Auth + Storage) |
| Local Database | Sqflite (Offline Support) |
| Navigation | GoRouter |
| UI | Flutter Animate, Iconsax, Google Fonts |
| Export | PDF, CSV |

## 🌟 Features & Roadmap

- [x] **Authentication**: Email/Password login, User profiles.
- [x] **Trip Management**: Create trips, invite via code, manage participants.
- [x] **Ledger**:
    - Expense tracking with support for multiple currencies.
    - "Omni-Splitter" for complex expense splitting.
    - Settlements and balance calculation.
- [x] **Gear**: Collaborative packing lists and gear assignment.
- [x] **Logistics**: Manage travel plans (flights, hotels, etc.).
- [x] **Vault**: Secure file storage for trip documents.
- [x] **Offline Mode**: Local caching and sync queue using Sqflite.
- [x] **Activity Log**: Audit trail for trip changes.

## 📄 License

MIT License - See LICENSE file for details.
