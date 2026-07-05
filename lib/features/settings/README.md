## settings/ — User Profile, Preferences & Account

### providers/
- **profile_stats_provider.dart**: Aggregate user stats (total spending, group count, event count) computed from the user's groups.

### screens/
- **profile_screen.dart**: Identity card (avatar + display name + edit name sheet + @handle chip — the QR sheet was removed in #840, no honest per-user payload existed to scan), stats grid, notifications toggle, theme + language + default-split pickers, linked-email + sign-out section, legal links sheet, about card, version. `showBack` constructor param avoids the `canPop` probe crash when rendered inside `BottomNavShell`. There is no global currency picker; groups choose their default currency at create time and balances render per-currency buckets.

### widgets/
- **edit_name_bottom_sheet.dart** — display-name editor with validation matching `security/firestore.rules`.
- **profile_display_section.dart** — Theme tile that opens `ThemePickerSheet`.
- **theme_picker_sheet.dart** — light / dark / system.
- **language_picker_sheet.dart** — English / Arabic; both live and selectable (Arabic unlocked in PR2a; Settings + Profile surfaces are translated, other surfaces follow in later PRs).
- **default_split_picker_sheet.dart** — `SplitMode` picker for new expenses (now fully unlocked after T4.N shipped).
- **legal_links_sheet.dart** — bottom sheet listing Terms / Privacy / Delete My Data; opens external URLs from `AppLinks`.
