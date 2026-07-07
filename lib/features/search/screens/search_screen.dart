import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/r_icon_button.dart';
import '../keys/search_keys.dart';
import '../widgets/search_results.dart';

/// Global cross-group search (#900 friction #3 — PR-5b, Gate-cleared:
/// `docs/plans/2026-07-05-falaj-pr5b-search-spec.md`).
///
/// v1 scope: groups + events (open AND closed) matched by name,
/// case-insensitive substring. Full expense search is Option C (deferred —
/// needs a server index); this screen never watches expense/settlement
/// providers.
///
/// `/search` is a TOP-LEVEL, route-only screen — its back-guard precedent is
/// [GroupDetailScreen] (`group_detail_screen.dart:66-76`), not the #666
/// dual-mode rule (that only applies to screens that are ALSO a
/// `BottomNavShell` tab; this one never is).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.query});

  /// Seeds the field from `?q=`. Typing updates results locally — no need to
  /// push every keystroke into the URL.
  final String? query;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;
  late String _query;

  @override
  void initState() {
    super.initState();
    _query = (widget.query ?? '').trim();
    _controller = TextEditingController(text: _query)
      ..addListener(_onQueryChanged);
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new `/search?q=…` deep link can land on the ALREADY-MOUNTED screen — its
    // go_router pageKey is path-based (query-blind), so the page reconciles in
    // place instead of remounting and `initState` never re-runs (#1027). Resync
    // the field here, but ONLY when the ROUTE query itself changed: comparing
    // against `oldWidget.query` (not the user-driven `_query`) stops a spurious
    // parent rebuild from clobbering in-progress typing.
    // NB: this warm-reseed path only fires because the deep link reaches
    // go_router (native platform deep-linking; see #369 /
    // ios_deep_linking_guard_test.dart) — the two are coupled.
    final incoming = (widget.query ?? '').trim();
    if (incoming == (oldWidget.query ?? '').trim()) return;
    _query = incoming;
    _controller.value = TextEditingValue(
      text: incoming,
      selection: TextSelection.collapsed(offset: incoming.length),
    );
  }

  void _onQueryChanged() {
    final next = _controller.text.trim();
    if (next != _query) setState(() => _query = next);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _backOrHome(BuildContext context) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _backOrHome(context);
      },
      child: Scaffold(
        key: SearchKeys.screen,
        backgroundColor: context.colors.scaffoldBackground,
        body: SafeArea(
          child: Column(
            children: [
              _SearchHeader(
                controller: _controller,
                onBack: () => _backOrHome(context),
              ),
              Expanded(child: SearchResults(query: _query)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({required this.controller, required this.onBack});

  final TextEditingController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        context.spacing.space12,
        context.spacing.space8,
        context.spacing.space16,
        context.spacing.space8,
      ),
      child: Row(
        children: [
          RIconButton(
            variant: RIconButtonVariant.ghost,
            icon: Directionality.of(context) == TextDirection.rtl
                ? Iconsax.arrow_right
                : Iconsax.arrow_left,
            tooltip: context.l10n.commonBack,
            onTap: () {
              HapticService.lightClick();
              onBack();
            },
          ),
          SizedBox(width: context.spacing.space8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colors.inputFill,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: context.spacing.space12,
              ),
              child: Row(
                children: [
                  Icon(
                    Iconsax.search_normal,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  SizedBox(width: context.spacing.space8),
                  Expanded(
                    child: TextField(
                      key: SearchKeys.field,
                      controller: controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: context.l10n.searchHint,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                      style: AppTypography.sans(
                        fontSize: 15,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
