import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/safe_deserialize.dart';
import '../../groups/models/group_activity_log_model.dart';
import '../../groups/models/group_model.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../../groups/services/group_activity_service.dart';
import 'dashboard_providers.dart';
import 'merged_activity_paginator.dart';

/// Per-group page size for the cross-group Activity tab. Reuses the per-group
/// history precedent (`fetchActivityPageRaw` default 50).
const int kCrossGroupActivityPageSize = 50;

/// Immutable state for the cross-group Activity tab (#808 PR2).
///
/// The tab is one-shot + pull-to-refresh (D-PR2-3): it does NOT stream. Home
/// RECENTLY and the unread dot keep reading the live `crossGroupActivityProvider`
/// — this pager is a parallel surface, not a replacement.
class CrossGroupActivityPagerState {
  const CrossGroupActivityPagerState({
    this.entries = const [],
    this.isLoadingMore = false,
    this.hasMore = true,
    this.firstLoadFailed = false,
    this.partialFailure = false,
    this.initialised = false,
  });

  /// Emitted, group-enriched entries — append-only within a load session.
  final List<CrossGroupActivityEntry> entries;
  final bool isLoadingMore;
  final bool hasMore;

  /// The FIRST load found groups but every one failed (entries empty) — drives
  /// the full #488 error view.
  final bool firstLoadFailed;

  /// At least one group's fetch failed (but not the whole first load) — drives
  /// the compact retry footer (#244 OR-drop: survivors still render).
  final bool partialFailure;

  /// The first load attempt has completed (success, empty, or failure).
  final bool initialised;

  CrossGroupActivityPagerState copyWith({
    List<CrossGroupActivityEntry>? entries,
    bool? isLoadingMore,
    bool? hasMore,
    bool? firstLoadFailed,
    bool? partialFailure,
    bool? initialised,
  }) => CrossGroupActivityPagerState(
    entries: entries ?? this.entries,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore: hasMore ?? this.hasMore,
    firstLoadFailed: firstLoadFailed ?? this.firstLoadFailed,
    partialFailure: partialFailure ?? this.partialFailure,
    initialised: initialised ?? this.initialised,
  );
}

class _FetchOutcome {
  const _FetchOutcome({
    required this.groupId,
    required this.logs,
    required this.rawCount,
    required this.cursor,
    required this.failed,
  });
  final String groupId;
  final List<GroupActivityLog>? logs;

  /// #928: the RAW page size (`snap.docs.length`), BEFORE the malformed-row
  /// fence drops any doc. Exhaustion must derive from this, not `logs.length`:
  /// a full raw page (== page size) that decodes short because a row was skipped
  /// is NOT the last page — deriving exhaustion from the deserialized count
  /// would falsely drain the group and silently truncate its older activity.
  final int rawCount;
  final DocumentSnapshot? cursor;
  final bool failed;
}

/// Cursor-paginated, cross-group merge notifier (#808 PR2).
///
/// Owns the Firestore side: one [DocumentSnapshot] cursor per group and the
/// `fetchActivityPageRaw` calls (do NOT re-implement the query — the
/// cursor-then-limit trap is already solved there, #183). Ordering + frontier
/// live in the pure [mergeAvailable]. Per-group try/catch keeps one failing
/// group from sinking the page (#244).
class CrossGroupActivityPagerNotifier
    extends StateNotifier<CrossGroupActivityPagerState> {
  CrossGroupActivityPagerNotifier(this._ref)
    : super(const CrossGroupActivityPagerState(isLoadingMore: true)) {
    _reload();
  }

  final Ref _ref;

  Map<String, GroupPageState> _states = {};
  final Map<String, DocumentSnapshot?> _cursors = {};
  final Map<String, ({String name, String currency})> _ctx = {};
  Set<String> _needsFetch = {};
  int _groupCount = 0;

  GroupActivityService get _service =>
      _ref.read(groupActivityServiceProvider);

  CrossGroupActivityEntry _enrich(MergedActivityEntry e) {
    final ctx = _ctx[e.groupId];
    return (
      log: e.log,
      groupName: ctx?.name ?? '',
      groupId: e.groupId,
      currency: ctx?.currency ?? 'OMR',
    );
  }

  Future<_FetchOutcome> _fetchOne(String groupId) async {
    try {
      final snap = await _service.fetchActivityPageRaw(
        groupId,
        startAfter: _cursors[groupId],
        limit: kCrossGroupActivityPageSize,
      );
      // #928: skip a malformed row instead of letting it throw into the
      // per-group catch below, which would drop the WHOLE group from the merged
      // feed. Display-only feed rows: skip-and-report is the correct semantic.
      final logs = decodeDocsSkippingMalformed(
        snap.docs,
        (d) => GroupActivityLog.fromFirestore(
          {...d.data()! as Map<String, dynamic>, 'id': d.id},
        ),
        context: 'CrossGroupActivity.fetch',
      )
        // Deterministic within-group tiebreak (ts desc, then id asc) so the
        // merge total order holds even for same-timestamp entries.
        ..sort((a, b) {
          final byTime = b.timestamp.compareTo(a.timestamp);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
      return _FetchOutcome(
        groupId: groupId,
        logs: logs,
        rawCount: snap.docs.length,
        cursor: snap.docs.isNotEmpty ? snap.docs.last : _cursors[groupId],
        failed: false,
      );
    } catch (_) {
      return _FetchOutcome(
        groupId: groupId,
        logs: null,
        rawCount: 0, // unused on the failed path (exhausted is left untouched)
        cursor: _cursors[groupId],
        failed: true,
      );
    }
  }

  /// Fetch the currently-needed groups in parallel, fold results into the
  /// per-group state, then run one merge pass. Applies outcomes sequentially
  /// (after `Future.wait`) so the shared state can never be raced.
  Future<MergeResult> _fetchNeeded() async {
    final toFetch = _needsFetch.toList();
    final outcomes = await Future.wait(toFetch.map(_fetchOne));

    final next = Map<String, GroupPageState>.of(_states);
    for (final o in outcomes) {
      final prev = next[o.groupId]!;
      if (o.failed) {
        next[o.groupId] = prev.copyWith(failed: true);
      } else {
        next[o.groupId] = prev.copyWith(
          buffer: [...prev.buffer, ...o.logs!],
          // #928: exhaustion from the RAW page count, not the fenced/decoded
          // count — a full raw page that lost a malformed row is NOT drained.
          exhausted: o.rawCount < kCrossGroupActivityPageSize,
          failed: false,
        );
        _cursors[o.groupId] = o.cursor;
      }
    }
    _states = next;

    final result = mergeAvailable(_states);
    _states = result.states;
    _needsFetch = result.needsFetch;
    return result;
  }

  /// Full (re)load — the constructor path and pull-to-refresh. Rebuilds the
  /// group set from [userGroupsProvider] and REPLACES the visible list.
  Future<void> _reload() async {
    List<Group> groups;
    try {
      groups = await _ref.read(userGroupsProvider.future);
    } catch (_) {
      if (!mounted) return;
      state = const CrossGroupActivityPagerState(
        initialised: true,
        hasMore: false,
        firstLoadFailed: true,
      );
      return;
    }

    _ctx
      ..clear()
      ..addAll({
        for (final g in groups) g.id: (name: g.name, currency: g.currency),
      });
    _cursors
      ..clear()
      ..addAll({for (final g in groups) g.id: null});
    _states = {for (final g in groups) g.id: GroupPageState(groupId: g.id)};
    _needsFetch = {for (final g in groups) g.id};
    _groupCount = groups.length;

    if (groups.isEmpty) {
      if (!mounted) return;
      state = const CrossGroupActivityPagerState(
        initialised: true,
        hasMore: false,
      );
      return;
    }

    final result = await _fetchNeeded();
    if (!mounted) return;
    final emitted = [for (final e in result.emitted) _enrich(e)];
    final allFailed = result.failedGroups.length == _groupCount;
    final firstLoadFailed = emitted.isEmpty && allFailed && _groupCount > 0;
    state = CrossGroupActivityPagerState(
      entries: emitted,
      isLoadingMore: false,
      hasMore: result.hasMore,
      firstLoadFailed: firstLoadFailed,
      partialFailure: result.failedGroups.isNotEmpty && !firstLoadFailed,
      initialised: true,
    );
  }

  /// Scroll-near-bottom prefetch: fetch only the groups the frontier is waiting
  /// on and append the newly-safe entries.
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || _needsFetch.isEmpty) return;
    state = state.copyWith(isLoadingMore: true);
    final result = await _fetchNeeded();
    if (!mounted) return;
    state = state.copyWith(
      entries: [...state.entries, for (final e in result.emitted) _enrich(e)],
      isLoadingMore: false,
      hasMore: result.hasMore,
      partialFailure: result.failedGroups.isNotEmpty,
    );
  }

  /// Pull-to-refresh: reset cursors + buffers and reload page one. Old entries
  /// stay visible under the spinner until the fresh page lands.
  Future<void> refresh() async {
    if (state.isLoadingMore) return;
    state = state.copyWith(
      isLoadingMore: true,
      firstLoadFailed: false,
      partialFailure: false,
    );
    await _reload();
  }

  /// Retry the failed groups only (clears their `failed` flag and re-fetches
  /// from their existing cursor).
  Future<void> retryFailed() async {
    if (state.isLoadingMore) return;
    final failed = {
      for (final s in _states.values)
        if (s.failed) s.groupId,
    };
    if (failed.isEmpty) return;
    final next = Map<String, GroupPageState>.of(_states);
    for (final gid in failed) {
      next[gid] = next[gid]!.copyWith(failed: false);
    }
    _states = next;
    _needsFetch = {
      for (final s in _states.values)
        if (!s.exhausted && !s.failed && s.buffer.isEmpty) s.groupId,
    };
    state = state.copyWith(isLoadingMore: true);
    final result = await _fetchNeeded();
    if (!mounted) return;
    state = state.copyWith(
      entries: [...state.entries, for (final e in result.emitted) _enrich(e)],
      isLoadingMore: false,
      hasMore: result.hasMore,
      partialFailure: result.failedGroups.isNotEmpty,
    );
  }
}

/// The cross-group Activity tab pager. Non-autoDispose: the tab is always
/// mounted in [BottomNavShell], and preserving paged state across tab switches
/// avoids a refetch on every visit. Home + the unread dot do NOT read this.
final crossGroupActivityPagerProvider =
    StateNotifierProvider<
      CrossGroupActivityPagerNotifier,
      CrossGroupActivityPagerState
    >(CrossGroupActivityPagerNotifier.new);
