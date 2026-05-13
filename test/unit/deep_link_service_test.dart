import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/deep_link_service.dart';

void main() {
  group('DeepLinkService.parseJoinLink', () {
    final service = DeepLinkService.instance;

    Uri? parse(String link) => service.parseJoinLink(Uri.parse(link));

    test('normalizes custom scheme query join links', () {
      expect(parse('rihla://join?code=ABC123'), Uri(path: '/join/ABC123'));
    });

    test('normalizes custom scheme path join links', () {
      expect(parse('rihla://join/ABC123'), Uri(path: '/join/ABC123'));
    });

    test('normalizes universal link path join links', () {
      expect(parse('https://rihla.app/join/ABC123'), Uri(path: '/join/ABC123'));
    });

    test('normalizes universal link query join links', () {
      expect(
        parse('https://rihla.app/join?code=ABC123'),
        Uri(path: '/join/ABC123'),
      );
    });

    test('compares scheme and host case-insensitively', () {
      expect(parse('RIHLA://JOIN/abc123'), Uri(path: '/join/ABC123'));
      expect(parse('HTTPS://RIHLA.APP/join/abc123'), Uri(path: '/join/ABC123'));
    });

    test('trims and uppercases invite codes', () {
      expect(
        parse('https://rihla.app/join?code=%20abc123%20'),
        Uri(path: '/join/ABC123'),
      );
    });

    test(
      'uses the path segment when both segment and query code are present',
      () {
        expect(
          parse('https://rihla.app/join/abc123?code=ZZZ999'),
          Uri(path: '/join/ABC123'),
        );
      },
    );

    test('rejects non-join links', () {
      expect(parse('safar://join?code=ABC123'), isNull);
      expect(parse('https://example.com/join/ABC123'), isNull);
      expect(parse('https://rihla.app/groups/ABC123'), isNull);
    });

    test('rejects missing or empty invite codes', () {
      expect(parse('rihla://join'), isNull);
      expect(parse('rihla://join?code='), isNull);
      expect(parse('https://rihla.app/join'), isNull);
      expect(parse('https://rihla.app/join?code='), isNull);
    });

    test('rejects invalid invite code formats', () {
      expect(parse('rihla://join?code=ABC12'), isNull);
      expect(parse('rihla://join?code=ABC1234'), isNull);
      expect(parse('rihla://join?code=ABC-12'), isNull);
      expect(parse('https://rihla.app/join/ABC_12'), isNull);
    });
  });
}
