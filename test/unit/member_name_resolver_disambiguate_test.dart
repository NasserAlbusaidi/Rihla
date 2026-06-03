import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/groups/services/member_name_resolver.dart';

/// TDD RED — cluster `settle-up-same-name-discriminator` (#196), T1.
///
/// Sibling of `test/unit/member_name_resolver_test.dart`. At GREEN time these
/// cases should be merged into that file (kept separate now to avoid clobber).
///
/// Asserts the POST-FIX contract for the not-yet-existing
/// `MemberNameResolver.disambiguate` + `stripDiscriminator`. Until the resolver
/// gains those members this file does not compile → failureKind=not-implemented.
void main() {
  MemberDisplay live(String name) => MemberDisplay(rawName: name, isFormer: false);
  MemberDisplay former(String name) => MemberDisplay(rawName: name, isFormer: true);

  group('MemberNameResolver.disambiguate', () {
    test('two live members with the same name both get distinct (#…) suffixes',
        () {
      final result = MemberNameResolver.disambiguate({
        'uid-aaaa1111': live('Sam'),
        'uid-bbbb2222': live('Sam'),
      });

      expect(result['uid-aaaa1111'], 'Sam (#1111)');
      expect(result['uid-bbbb2222'], 'Sam (#2222)');
    });

    test('no collision → names returned verbatim, no discriminator', () {
      final result = MemberNameResolver.disambiguate({
        'u1': live('Sam'),
        'u2': live('Lena'),
      });

      expect(result['u1'], 'Sam');
      expect(result['u2'], 'Lena');
      expect(result['u1'], isNot(contains('(#')));
      expect(result['u2'], isNot(contains('(#')));
    });

    test('collision detection is case- and whitespace-insensitive', () {
      final result = MemberNameResolver.disambiguate({
        'u1': live('Sam '),
        'u2': live('sam'),
      });

      expect(result['u1'], contains('(#'));
      expect(result['u2'], contains('(#'));
    });

    test(
        'live + former with the same name → only the live Sam stays "Sam"; '
        'the former keeps "(former member)" with NO discriminator', () {
      final result = MemberNameResolver.disambiguate({
        'u1': live('Sam'),
        'u2': former('Sam'),
      });

      // Only ONE live Sam → no discriminator on the live entry.
      expect(result['u1'], 'Sam');
      // Former suffix already disambiguates; never double-tag.
      expect(result['u2'], 'Sam (former member)');
      expect(result['u2'], isNot(contains('(#')));
    });

    test('uid length <= 4 → the whole uid is used as the discriminator', () {
      final result = MemberNameResolver.disambiguate({
        'ab': live('Sam'),
        'cd': live('Sam'),
      });

      expect(result['ab'], 'Sam (#ab)');
      expect(result['cd'], 'Sam (#cd)');
    });

    test('does not mutate the input map (immutability)', () {
      final input = {
        'uid-aaaa1111': live('Sam'),
        'uid-bbbb2222': live('Sam'),
      };

      final result = MemberNameResolver.disambiguate(input);

      // Fresh map, originals untouched.
      expect(identical(result, input), isFalse);
      expect(input['uid-aaaa1111']!.rawName, 'Sam');
      expect(input['uid-bbbb2222']!.rawName, 'Sam');
    });
  });

  group('MemberNameResolver.stripDiscriminator', () {
    test('removes a trailing (#abcd) discriminator', () {
      expect(MemberNameResolver.stripDiscriminator('Sam (#ab12)'), 'Sam');
    });

    test('leaves an undiscriminated name untouched', () {
      expect(MemberNameResolver.stripDiscriminator('Sam'), 'Sam');
    });

    test('strips both the former suffix and a discriminator (defensive R2)', () {
      // The settle_up_page_body fallback may receive a discriminated name if
      // rawNames is somehow missing a uid — the stored payerName must never
      // carry "(#…)".
      expect(
        MemberNameResolver.stripDiscriminator('Sam (#ab12) (former member)'),
        'Sam',
      );
    });
  });
}
