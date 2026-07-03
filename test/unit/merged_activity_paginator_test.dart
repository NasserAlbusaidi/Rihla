import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/home/providers/merged_activity_paginator.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

GroupActivityLog _log(String id, int day) => GroupActivityLog(
  id: id,
  type: 'expense_added',
  actorId: 'u',
  actorName: 'A',
  description: 'd',
  // Distinct calendar days give distinct, comparable timestamps.
  timestamp: DateTime.utc(2026, 1, day),
);

GroupActivityLog _logAt(String id, DateTime ts) => GroupActivityLog(
  id: id,
  type: 'expense_added',
  actorId: 'u',
  actorName: 'A',
  description: 'd',
  timestamp: ts,
);

GroupPageState _state(
  String groupId,
  List<GroupActivityLog> buffer, {
  bool exhausted = false,
  bool failed = false,
}) => GroupPageState(
  groupId: groupId,
  buffer: buffer,
  exhausted: exhausted,
  failed: failed,
);

Map<String, GroupPageState> _states(List<GroupPageState> list) => {
  for (final s in list) s.groupId: s,
};

List<String> _emittedIds(MergeResult r) => r.emitted.map((e) => e.log.id).toList();

void main() {
  group('mergeAvailable — emission contract', () {
    test('two groups interleaved; frontier holds back the tail', () {
      // gA still active with an old tail entry; gB active but its buffer
      // empties, so the frontier must hold back gA's oldest until gB refetches.
      final r = mergeAvailable(
        _states([
          _state('gA', [_log('a3', 30), _log('a1', 10)]),
          _state('gB', [_log('b2', 20)]),
        ]),
      );

      // a3 (30) then b2 (20); a1 (10) held back — gB (non-exhausted) emptied.
      expect(_emittedIds(r), ['a3', 'b2']);
      expect(r.needsFetch, {'gB'});
      expect(r.hasMore, isTrue);
      // a1 must still be buffered on gA (not lost).
      expect(r.states['gA']!.buffer.map((e) => e.id), ['a1']);
    });

    test('an exhausted group drains fully alongside an active group', () {
      // gA exhausted with a two-entry buffer; gB active but all older, so gA's
      // whole buffer drains without gB blocking (gB is the frontier, older).
      final r = mergeAvailable(
        _states([
          _state('gA', [_log('a2', 20), _log('a1', 10)], exhausted: true),
          _state('gB', [_log('b0', 5)]),
        ]),
      );

      expect(_emittedIds(r), ['a2', 'a1', 'b0']);
      expect(r.needsFetch, {'gB'});
      expect(r.states['gA']!.buffer, isEmpty);
      expect(r.hasMore, isTrue);
    });

    test('equal timestamps tiebreak by groupId asc, then log.id asc', () {
      final ts = DateTime.utc(2026, 1, 1);
      // Cross-group: groupId asc beats log.id asc — gA's "x" outranks gB's "a".
      final r = mergeAvailable(
        _states([
          _state('gA', [_logAt('x', ts)], exhausted: true),
          _state('gB', [_logAt('a', ts)], exhausted: true),
        ]),
      );
      expect(_emittedIds(r), ['x', 'a']);

      // Within one group, same ts → buffer order (notifier feeds id-asc sorted).
      final r2 = mergeAvailable(
        _states([
          _state('gC', [_logAt('a1', ts), _logAt('a2', ts)], exhausted: true),
        ]),
      );
      expect(_emittedIds(r2), ['a1', 'a2']);
    });

    test('single group degenerates to plain pagination', () {
      final r = mergeAvailable(
        _states([
          _state('gA', [_log('a3', 30), _log('a2', 20), _log('a1', 10)]),
        ]),
      );
      expect(_emittedIds(r), ['a3', 'a2', 'a1']);
      // Buffer drained; the sole group is non-exhausted → needs its next page.
      expect(r.needsFetch, {'gA'});
      expect(r.hasMore, isTrue);
    });

    test('all groups exhausted → drains fully, hasMore false', () {
      final r = mergeAvailable(
        _states([
          _state('gA', [_log('a2', 20), _log('a1', 10)], exhausted: true),
          _state('gB', [_log('b1', 15)], exhausted: true),
        ]),
      );
      expect(_emittedIds(r), ['a2', 'b1', 'a1']);
      expect(r.needsFetch, isEmpty);
      expect(r.hasMore, isFalse);
      expect(r.states.values.every((s) => s.buffer.isEmpty), isTrue);
    });

    test('failed group does not block emission and is reported for retry', () {
      final r = mergeAvailable(
        _states([
          _state('gA', [_log('a2', 20)]),
          _state('gB', const [], failed: true),
        ]),
      );
      expect(_emittedIds(r), ['a2']);
      // gB is failed → excluded from needsFetch (retry is an explicit action).
      expect(r.needsFetch, {'gA'});
      expect(r.failedGroups, {'gB'});
      // gA non-exhausted → still more.
      expect(r.hasMore, isTrue);
    });

    test('failed group with all others exhausted: drains, hasMore false, '
        'still flagged', () {
      final r = mergeAvailable(
        _states([
          _state('gA', [_log('a1', 10)], exhausted: true),
          _state('gB', const [], failed: true),
        ]),
      );
      expect(_emittedIds(r), ['a1']);
      expect(r.hasMore, isFalse);
      expect(r.needsFetch, isEmpty);
      expect(r.failedGroups, {'gB'});
    });

    test('exactly pageSize: exhaustion only discovered on the empty next page',
        () {
      const pageSize = 50;
      final full = [for (var i = pageSize; i >= 1; i--) _log('a$i', i)];
      // Round 1: a full page → not exhausted; drains, then needs a next page.
      final r1 = mergeAvailable(
        _states([_state('gA', full)]),
      );
      expect(r1.emitted, hasLength(pageSize));
      expect(r1.needsFetch, {'gA'});
      expect(r1.hasMore, isTrue);

      // Round 2: the notifier fetched 0 docs → exhausted, empty buffer.
      final r2 = mergeAvailable(
        _states([_state('gA', const [], exhausted: true)]),
      );
      expect(r2.emitted, isEmpty);
      expect(r2.needsFetch, isEmpty);
      expect(r2.hasMore, isFalse);
    });

    test('is pure — does not mutate the input states', () {
      final buf = [_log('a2', 20), _log('a1', 10)];
      final input = _states([_state('gA', buf)]);
      mergeAvailable(input);
      // Original buffer untouched.
      expect(input['gA']!.buffer, hasLength(2));
      expect(buf, hasLength(2));
    });
  });
}
