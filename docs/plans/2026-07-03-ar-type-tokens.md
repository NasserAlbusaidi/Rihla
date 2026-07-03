# PR-8 — Per-script typography tokens: Arabic drops mono tracking and synthetic italics (#841)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> **Provenance:** Option B of `docs/design/mockups/841-arabic-type.html`, user-signed-off 2026-07-03. Call-site map: fresh mapper vs `b0e02329`; API claims orchestrator-spot-checked same commit.

**Goal:** Arabic text stops inheriting Latin-only treatments — no `letterSpacing` on joined script (mono captions), no synthetic italic (display) — while EN/Latin rendering stays byte-identical and money/code surfaces stay Geist Mono in every locale.

**The signed-off contract (three rules):**
1. AR captions = sans-fallback **w700 / ≥11px / letterSpacing 0** (uppercase is a no-op in Arabic — callers keep their `.toUpperCase()`, zero call-site text-transform churn).
2. AR display = **upright w500** (no synthetic italic).
3. Numerals/codes stay **Geist Mono everywhere** (amounts, dates-as-figures, invite codes, currency codes; tabular alignment preserved).

---

## 1. Token API (`lib/core/theme/tokens/typography_tokens.dart`)

Two NEW context-aware statics + one doc rewrite. `display()`, `sans()`, `mono()`, `arabicDisplay()` signatures are UNTOUCHED (context-free consumers + test pins depend on them).

```dart
/// Small caps-style caption for TRANSLATABLE copy (section headers, eyebrows,
/// action links, meta lines). Latin: the classic mono recipe, unchanged.
/// Arabic: mono tracking visually disconnects joined letters, so the caption
/// re-expresses its role as sans w700, letterSpacing 0, floor 11px.
/// Callers keep `.toUpperCase()` — it is a no-op on Arabic script.
static TextStyle caption(
  BuildContext context, {
  required double fontSize,
  Color? color,
  FontWeight fontWeight = FontWeight.w500, // MUST match mono()'s default — see Gate r1 [P1]
  double? letterSpacing,
  double? height,
}) {
  final isArabic = Localizations.localeOf(context).languageCode == 'ar'; // wordmark_logo.dart:39 idiom
  if (!isArabic) {
    return mono(fontSize: fontSize, color: color, fontWeight: fontWeight,
        letterSpacing: letterSpacing, height: height);
  }
  return sans(fontSize: math.max(fontSize, 11), color: color,
      fontWeight: FontWeight.w700, letterSpacing: 0, height: height);
}

/// Locale-aware display. Latin: italic Instrument Serif (unchanged).
/// Arabic: Instrument Serif carries no Arabic glyphs — the renderer falls back
/// to the system face; upright w500 replaces the synthetic slant.
static TextStyle displayOf(
  BuildContext context, {
  required double fontSize,
  Color? color,
  FontWeight? fontWeight,
  double? letterSpacing,
  double? height,
  bool italic = true,
}) {
  final isArabic = Localizations.localeOf(context).languageCode == 'ar';
  if (!isArabic) {
    return display(fontSize: fontSize, color: color,
        fontWeight: fontWeight ?? FontWeight.w400,
        letterSpacing: letterSpacing, height: height, italic: italic);
  }
  return display(fontSize: fontSize, color: color,
      fontWeight: fontWeight ?? FontWeight.w500,
      letterSpacing: 0, height: height, italic: false);
}
```

- `mono()`'s doc comment (currently "…and any small uppercase caption" at typography_tokens.dart:110-111) is rewritten **numerals-only**: money amounts, currency codes, invite codes, dates-as-figures, version strings — never translatable copy (that's `caption()`), never user free-text (that's `sans()`).
- `import 'dart:math' as math;` (or a manual ternary) for the 11px floor.
- **`caption()`'s EN default weight is `w500` — identical to `mono()`'s default (typography_tokens.dart:115) — NOT w600.** ~13 migrate sites call `mono(...)` with no `fontWeight` and rely on the w500 default (`home_screen.dart:336,683`, `activity_feed_screen.dart:243`, `custom_split_sheet_chrome.dart:115`, `group_detail_screen.dart:519,945`, `qr_invite_sheet.dart:92`, `cross_group_activity_screen.dart:753`, `activity_row.dart:101`, `journey_ticket_card.dart:77`, `ledger_screen.dart:423,570`, `group_activity_screen.dart:569`, `event_command_center.dart:394`); a w600 default would silently heavy every one of them under EN, breaking the byte-identical invariant. Explicit-weight sites (`section_header.dart:45` passes w600) are unaffected.

## 2. Migration map (from the b0e02329 call-site census: 72 mono, 54 display)

**mono → `caption(context, …)` — Latin params preserved verbatim** (same fontSize/weight/spacing so the EN path is byte-identical):
- Chokepoints (cover ~19 consumers in 4 edits): `lib/shared/widgets/section_header.dart:45` (11/w600/1.2), `lib/features/groups/widgets/settings_section_header.dart:31` (…/1.5), `_ItemizedSectionHeader` `custom_split_sheet_itemized.dart:267`, `_microLabel` `recap_share_card.dart:546`.
- Raw caption sites: `home_screen.dart:336`, `profile_screen.dart:886,934` (ARB strings authored ALL-CAPS — no `.toUpperCase()` present, none added), `activity_feed_screen.dart:243`, `custom_split_sheet_itemized.dart:1084`, `custom_split_sheet_chrome.dart:115`, `ledger_roster_strip.dart:259`, `ledger_day_card.dart:503`, `split_card.dart:217,366`, `ledger_hero_block.dart:253,289,301` (:289/:301 = `LedgerTripCaption` label `label ?? l10n.ledgerTripTotal` + tail `ledgerExpenseCount · ledgerSettledCount` — ARB-translatable; live via `ledger_screen.dart:307`), `group_detail_screen.dart:519,945`, `group_stamp_picker.dart:163`, `group_spending_summary_section.dart:225`, `qr_invite_sheet.dart:92`, `recap_share_card.dart:143` (cover-band caption `l10n.recapCardCaption` — translated to Arabic script in app_ar.arb:1069, so NOT brand-Latin like the :497 footer; builder-caught post-Gate).
- MIXED sites that are captions in role (dates/relative-times/ARB-with-embeds — localized words under AR): `home_screen.dart:683` (greeting), `cross_group_activity_screen.dart:629,753`, `activity_feed_screen.dart:293,397` (:397 = `formatRelativeShort` → `activityRelative*` ARB, Arabic relative-time), `activity_row.dart:101`, `group_activity_screen.dart:451,569`, `journey_ticket_card.dart:77`, `ledger_screen.dart:423,570`, `expense_editor_body.dart:1123`, `ledger_day_card.dart:56`, `event_command_center.dart:394`.

**mono → `sans(…)` unconditional (user free-text must never be mono — rule 3's contrapositive):**
- `delete_group_sheet.dart:205,228` — the type-to-confirm GROUP NAME (mono breaks Arabic joins in a destructive-confirm flow, both the rendered name and the input the user must match). Preserve size/weight/color; drop letterSpacing.
- `ledger_day_card.dart:518` — user-authored settlement note.

**mono stays (numerals/codes/brand-Latin — untouched):** the full NUMERAL list (RAmount `r_amount.dart:97,103,110`, editor amount displays, split-sheet numeric fields/steppers/percents, balance signs, per-currency totals, `balance_hero_card.dart:98,246` currency codes, invite-code field/hint/pills `join_group_screen.dart:589,605` + `group_info_section.dart:168` + `qr_invite_sheet.dart:256` — Latin-only alphabet by design #293), `profile_screen.dart:1376` (hardcoded Latin brand literal 'RIHLA · …' — NOT ARB; do not "fix"), **`ledger_hero_block.dart:295`** (`LedgerTripCaption` per-currency trip-total `amountStyle` — MONEY; sits BETWEEN the two migrated caption lines :289/:301, do NOT sweep it), decorative dashes/dots (`ledger_roster_strip.dart:138,241`, `ledger_day_card.dart:67`, `ledger_hero_block.dart:310`).

**display → `displayOf(context, …)` — all AR-visible sites:**
- User-text sites (15): `group_detail_screen.dart:527`, `create_group_screen.dart:772`, `group_info_section.dart:116`, `ledger_screen.dart:581`, `event_command_center.dart:402`, `journey_ticket_card.dart:104`, `activity_feed_screen.dart:251`, `recap_share_card.dart:154`, `group_glyph.dart:69` + `group_stamp_picker.dart:251` + `profile_screen.dart:1636` (monogram letter — name-initial), `profile_screen.dart:424` (the user's own display name, free-text), `ledger_day_card.dart:38`, `settle_notify_sheet.dart:92`, `claim_join_views.dart:194`.
- ARB-title sites (~22): splash error title `splash_screen.dart:140`, `edit_name_bottom_sheet.dart:128`, `ledger_screen.dart:620`, `custom_split_sheet_itemized.dart:681,1020`, `custom_split_sheet_chrome.dart:35`, `ledger_category_strip.dart:227`, `join_group_screen.dart:464,487`, `create_group_screen.dart:484,552`, `group_edit_sheet.dart:162`, `add_shadow_member_sheet.dart:106`, `qr_invite_sheet.dart:69`, `claim_join_views.dart:38,145`, `record_payment_sheet.dart:249`, `delete_group_sheet.dart:129`, `event_command_center.dart:541`, `cross_group_activity_screen.dart:438`, `balance_hero_card.dart:89`, `group_detail_screen.dart:672`, `ledger_day_card.dart:75` (`LedgerDayStamp.sub` optional subtitle — ARB/date string).
- `ledger_hero_block.dart:129` (`numStyle` — the hero balance MONEY figure) **stays raw `display()` explicitly** (same class as `recap_share_card.dart:290`: pure stat figure, Latin digits). `:72,122`: migrate any fragment that renders ARB/user text; a fragment that is purely Latin digits/sign stays raw `display()` — builder decides per fragment, rule = "can this string ever contain Arabic?".

**display stays raw (named exceptions):**
- `app_theme.dart:44,244,384,391,398,406` — context-free cached `ThemeData` (#622 static pattern); currently DEAD slots (nothing in lib/ reads `textTheme.display*`/`headlineLarge`; all 4 in-app AppBars pass explicit styles or no title). Do not restructure; do not wire new consumers to these slots without a locale story (add this sentence to DESIGN.md).
- `splash_screen.dart:63,72` (wordmark 'R'/'Rihla' — brand Latin) and `recap_share_card.dart:497` (hardcoded 'Rihla' footer on the exported share image — ACCEPTED as brand-Latin; flagged, not changed).
- `recap_share_card.dart:290` (pure stat figure, Latin digits).

## 3. `docs/DESIGN.md` §3 rewrite (lines 115-130)

- mono row: "All money amounts, currency codes, invite codes, dates-as-figures. **Numerals/codes only — translatable captions use `caption()`; user free-text uses `sans()`.**"
- NEW caption row: "`AppTypography.caption(context, …)` — small caps-style captions/eyebrows. Latin = mono recipe; Arabic = sans w700, spacing 0, ≥11px (joined script rejects tracking; uppercase is a no-op)."
- display row: helper becomes "`AppTypography.displayOf(context, …)` (context-free `display()` reserved for the cached theme + brand-Latin)"; Use column names the reality: "wordmark, screen titles, hero numerals, **and entity names (user text)**; Arabic renders upright w500 — no synthetic italic."
- arabicDisplay row unchanged (wordmark-only).

## 4. Tests — RED-first

1. `test/unit/typography_tokens_test.dart` additions (pump a minimal `MaterialApp(locale:…)` to obtain a context, mirroring existing style):
   - `caption()` EN: fontFamily == mono's ('Geist Mono' + fallback), **w500 default — asserted equal to `mono()`'s default weight so a no-weight caller is byte-identical pre/post migration**, caller's letterSpacing preserved.
   - `caption()` AR: fontFamily == sans's ('Geist'), w700, letterSpacing 0, fontSize floor (pass 10.5 → expect 11).
   - `displayOf()` EN: `FontStyle.italic`, w400 default. AR: `FontStyle.normal`, w500 default, explicit `fontWeight` still honored; the `italic` argument is IGNORED under AR — always upright regardless (assert `italic: true` under AR still renders `FontStyle.normal`).
   - Existing pins (display default italic :69-77, `italic:false` :80-83, arabicDisplay never-italic :86-96) stay green — `display()` untouched.
2. Widget RED: `SectionHeader` under `Locale('ar')` → rendered `Text` style has letterSpacing 0 and non-mono family (write first — FAILS today with 'Geist Mono' + 1.2); same test file asserts the EN path is unchanged ('Geist Mono', spacing 1.2, uppercase text — `home_identity_polish_test.dart:206`'s EN pin must stay green).
3. Guards that must stay green untouched: `bundled_fonts_test.dart:138-160` arabicDisplay allow-list (neither new helper touches `arabicDisplay()` — the AR branches use sans/system-fallback, NOT the Reem Kufi subset), theme purity script, `prefer_const_constructors`.

## 5. Known limits (named, accepted)

- **Locale-based, not script-based:** an Arabic group name under the EN locale still hits mono/italic-serif fallback (script mismatch). Per-string script detection is out of scope — revisit with Option C (bundled Arabic face) at the 2.0 design pass. Exception carved out now: the two `delete_group_sheet` sites + the settlement note go to `sans()` unconditionally, which renders both scripts correctly.
- Goldens carry ZERO Arabic-locale coverage (grepped: no `Locale('ar')` under test/goldens/) — this surface is pinned by unit/widget tests only.
- The exported share card keeps a Latin 'Rihla' footer under AR (brand consistency on an outbound image).

## 6. Rollout

One PR (`feat/841-ar-type-tokens`): this spec doc + tokens + DESIGN.md + chokepoints + the mechanical sweep + tests. **Sweep rules:** (a) line numbers above are advisory — grep the cited expression at implementation time, don't trust the line (three cites drifted between mapping and review); (b) preserve EVERY effective param including the implicit weight default — a site calling `mono(...)` with no `fontWeight` becomes `caption(context, ...)` with no `fontWeight` and MUST render identically under EN (w500=w500). Commit `feat(theme): per-script caption/display tokens — Arabic drops mono tracking and synthetic italics` with body `Refs #841` (partial delivery — #841 cluster stays open) + `Spec: docs/plans/2026-07-03-ar-type-tokens.md`. `flutter analyze` clean, `bash tool/check_theme_purity.sh`, run: typography_tokens_test, the new SectionHeader AR test, bundled_fonts_test, home_identity_polish_test, plus the test files of every touched widget dir. `/automerge` (theme tokens + widget styling — expect EXEMPT, classify honestly on `--name-only`).

---

**Verification-principles record:** (1) every touched callsite is INBOUND — TextStyles render, nothing persists; no write boundary anywhere. (2) Concrete claims mapper-verified at `b0e02329`, orchestrator spot-checked signatures (typography_tokens.dart:44/71/112), the locale idiom (wordmark_logo.dart:39), the 6 context-free sites (app_theme.dart grep), SectionHeader recipe (:45-50). (3)/(4)/(6) n/a — no data-shape, no schema, no arithmetic. (5) Exact new-API signatures spelled in §1. (7) Orthogonal axes probed: **case-transform axis** — callers' `.toUpperCase()` is a no-op on Arabic so EN pins survive without call-site churn; **test-harness axis** — arabicDisplay allow-list guard and locale-pinned EN assertions named in §4; **script-vs-locale axis** — named as the accepted limit in §5 with the user-free-text carve-out.
