import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/utils/expense_provenance.dart';

// #248 PR5 — pure provenance-byline logic for the expense editor.
//
// Decides what the editor's "Added by … · edited by …" byline shows, given the
// expense's createdBy / lastEditedBy uids and a uid→name resolver. The realistic
// branches are identity-shaped: no creator (legacy), self-edit (creator ==
// editor), and a third-party edit (the case open editing actually creates).
void main() {
  // A resolver standing in for the disambiguated participantNames chain with an
  // "unknown → Someone" fallback (mirrors the widget's closure).
  String resolver(String uid) => switch (uid) {
    'uid-gemini' => 'Gemini',
    'uid-codex' => 'Codex',
    'uid-nasser' => 'Nasser',
    _ => 'Someone',
  };

  group('resolveExpenseProvenance', () {
    test('returns null when no creator is stamped (legacy expense)', () {
      expect(
        resolveExpenseProvenance(
          createdBy: '',
          lastEditedBy: '',
          resolveName: resolver,
        ),
        isNull,
      );
    });

    test('returns null when createdBy is empty even if lastEditedBy is set', () {
      // A legacy doc that only ever carried a (later) lastEditedBy still has no
      // attributable author for the "Added by" anchor → nothing to show.
      expect(
        resolveExpenseProvenance(
          createdBy: '',
          lastEditedBy: 'uid-codex',
          resolveName: resolver,
        ),
        isNull,
      );
    });

    test('creator only when lastEditedBy is empty', () {
      final p = resolveExpenseProvenance(
        createdBy: 'uid-gemini',
        lastEditedBy: '',
        resolveName: resolver,
      );
      expect(p, isNotNull);
      expect(p!.creatorName, 'Gemini');
      expect(p.editorName, isNull);
    });

    test('creator only when the last editor IS the creator (self-edit)', () {
      final p = resolveExpenseProvenance(
        createdBy: 'uid-gemini',
        lastEditedBy: 'uid-gemini',
        resolveName: resolver,
      );
      expect(p, isNotNull);
      expect(p!.creatorName, 'Gemini');
      expect(p.editorName, isNull);
    });

    test('creator + editor when a third party last edited', () {
      final p = resolveExpenseProvenance(
        createdBy: 'uid-gemini',
        lastEditedBy: 'uid-codex',
        resolveName: resolver,
      );
      expect(p, isNotNull);
      expect(p!.creatorName, 'Gemini');
      expect(p.editorName, 'Codex');
    });

    test('unknown uids fall back through the resolver to "Someone"', () {
      final p = resolveExpenseProvenance(
        createdBy: 'uid-departed',
        lastEditedBy: 'uid-also-gone',
        resolveName: resolver,
      );
      expect(p, isNotNull);
      expect(p!.creatorName, 'Someone');
      expect(p.editorName, 'Someone');
    });
  });
}
