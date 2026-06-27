import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/auth/services/auth_email_link_config.dart';
import 'package:safar/features/auth/services/auth_email_link_recognizer.dart';

Uri _validAuthLink({String oobCode = 'ABC123'}) => Uri.parse(
  'https://${AuthEmailLinkConfig.hostingDomain}'
  '${AuthEmailLinkConfig.continuePath}'
  '?mode=signIn&oobCode=$oobCode',
);

void main() {
  test('unwraps custom-scheme auth-link fallback', () {
    final uri = Uri(
      scheme: 'rihla',
      host: 'auth-link',
      queryParameters: {'link': _validAuthLink().toString()},
    );

    expect(emailLinkFromUri(uri), _validAuthLink().toString());
    expect(
      isRecognizedAuthEmailLink(uri, isFirebaseEmailLink: (_) => false),
      isTrue,
    );
  });

  test(
    'recognizes Firebase Auth email links through the shared fallback seam',
    () {
      final uri = Uri.parse(
        'https://example.test/action?mode=signIn&oobCode=X',
      );

      expect(
        isRecognizedAuthEmailLink(
          uri,
          isFirebaseEmailLink: (link) => link.contains('oobCode=X'),
        ),
        isTrue,
      );
    },
  );

  test('rejects non-auth links', () {
    expect(
      isRecognizedAuthEmailLink(
        Uri.parse('rihla://join/ABC123'),
        isFirebaseEmailLink: (_) => false,
      ),
      isFalse,
    );
  });
}
