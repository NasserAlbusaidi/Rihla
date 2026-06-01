## settings/ — User Profile, Preferences & Account

### providers/
- **profile_stats_provider.dart**: Aggregate user stats (total spending, group count, event count) computed from the user's groups.

### screens/
- **profile_screen.dart**: Identity card (avatar + display name + edit name sheet), QR profile sheet, stats grid, notifications toggle, theme + language + currency + default-split pickers, linked-email + sign-out section, legal links sheet, support link (feedback mailto; the donate URL is defined in `AppLinks.paypalUrl` but not yet surfaced — no `ProfileSupportSection` is wired in), about card, version. `showBack` constructor param avoids the `canPop` probe crash when rendered inside `BottomNavShell`.

### widgets/
- **edit_name_bottom_sheet.dart** — display-name editor with validation matching `security/firestore.rules`.
- **profile_display_section.dart** — Theme tile that opens `ThemePickerSheet`.
- **theme_picker_sheet.dart** — light / dark / system.
- **currency_picker_sheet.dart** — OMR / AED / SAR / USD / EUR / GBP. "Default for new trips" copy.
- **language_picker_sheet.dart** — English / Arabic; both live and selectable (Arabic unlocked in PR2a; Settings + Profile surfaces are translated, other surfaces follow in later PRs).
- **default_split_picker_sheet.dart** — `SplitMode` picker for new expenses (now fully unlocked after T4.N shipped).
- **profile_qr_sheet.dart** — QR code for the user's profile handle.
- **legal_links_sheet.dart** — bottom sheet listing Terms / Privacy / Delete My Data; opens external URLs from `AppLinks`.
