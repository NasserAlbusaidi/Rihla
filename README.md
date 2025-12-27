# Safar - Trip Planning App

A Flutter mobile app for group trip planning with expense splitting, gear tracking, and document sharing.

## 🚀 Getting Started

### Prerequisites

- Flutter SDK 3.10+
- A Supabase account (free tier works)

### 1. Set Up Supabase

1. Go to [supabase.com](https://supabase.com) and create a new project
2. Wait for the project to be provisioned
3. Go to **Settings > API** and copy:
   - Project URL
   - `anon` public key

### 2. Configure Environment

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your Supabase credentials:
   ```
   SUPABASE_URL=https://your-project-id.supabase.co
   SUPABASE_ANON_KEY=your-anon-key-here
   ```

### 3. Set Up Database

1. Go to your Supabase project's **SQL Editor**
2. Open `supabase/migrations/001_initial_schema.sql`
3. Copy and paste the entire SQL file into the SQL Editor
4. Click **Run** to create all tables and policies

### 4. Enable Authentication

1. Go to **Authentication > Providers**
2. Enable **Email** provider
3. Configure:
   - Enable "Confirm email" for production
   - Set site URL to your app's deep link (for mobile)

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
│   ├── config/
│   │   └── supabase_config.dart # Supabase client init
│   ├── router/
│   │   └── app_router.dart      # GoRouter configuration
│   └── theme/
│       └── app_theme.dart       # Dark theme
├── features/
│   ├── auth/                    # Authentication
│   │   ├── providers/
│   │   └── screens/
│   ├── trip/                    # Trip management
│   │   ├── models/
│   │   ├── providers/
│   │   └── screens/
│   └── home/                    # Command Center
│       └── screens/
└── shared/
    └── widgets/                 # Reusable components
```

## 🛠 Tech Stack

| Category | Technology |
|----------|------------|
| Framework | Flutter 3.10+ |
| State Management | Riverpod |
| Backend | Supabase (PostgreSQL + Auth) |
| Navigation | GoRouter |
| UI | Custom dark theme with glassmorphism |

## 📝 Development Roadmap

- [x] **Phase 1**: Authentication & Trip Creation
  - [x] Email/OTP Login
  - [x] Trip creation with invite code
  - [x] Join trip via code
  - [x] Command Center UI

- [ ] **Phase 2**: Core Ledger
  - [ ] Expense entry
  - [ ] Omni-Splitter engine
  - [ ] Balance calculations

- [ ] **Phase 3**: Sub-Groups & Gear
  - [ ] Car/Room management
  - [ ] Gear claiming system

- [ ] **Phase 4**: Document Vault
  - [ ] File upload to Supabase Storage
  - [ ] Offline mode with Hive

## 📄 License

MIT License - See LICENSE file for details.
