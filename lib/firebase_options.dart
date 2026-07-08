import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyATf9KyZzWmuwu2yYtPIE6uN_0eKipB8Og',
    appId: '1:231518921973:android:40159a929d53b8a353d1bc',
    messagingSenderId: '231518921973',
    projectId: 'rihla-safar',
    storageBucket: 'rihla-safar.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDbo2O9X7LasoP48a21u8NmuYurz0cUJz0',
    appId: '1:231518921973:ios:c8bfaa64d0f3a74c53d1bc',
    messagingSenderId: '231518921973',
    projectId: 'rihla-safar',
    storageBucket: 'rihla-safar.firebasestorage.app',
    androidClientId:
        '231518921973-fa68dddic1u2bo4efgpscm5tpi6d62da.apps.googleusercontent.com',
    iosClientId:
        '231518921973-husmvvkmm17gff534bo5r6j2ht9hat9m.apps.googleusercontent.com',
    iosBundleId: 'com.nalbusaidi.rihla',
  );
}
