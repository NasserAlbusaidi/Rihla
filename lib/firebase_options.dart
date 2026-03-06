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
    appId: '1:231518921973:ios:3be8191ea5b7b01353d1bc',
    messagingSenderId: '231518921973',
    projectId: 'rihla-safar',
    storageBucket: 'rihla-safar.firebasestorage.app',
    iosBundleId: 'com.safar.safar',
  );
}
