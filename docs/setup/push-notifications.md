# Push Notifications Setup

Rihla uses Firebase Cloud Messaging for device tokens. The current app registers and removes each user's token in Firestore at `fcm_tokens/{uid}` after notification opt-in.

## App Requirements

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- Firebase Messaging enabled for project `rihla-safar`
- iOS APNs key or certificate configured in Firebase Console before testing on iOS devices

## Runtime Behavior

- `NotificationService.initialize()` requests permission only after the user opts in.
- Accepted permissions save the FCM token to `fcm_tokens/{uid}` with `user_id`, `token`, `platform`, and `updated_at`.
- Token refreshes update the same Firestore document.
- Turning notifications off deletes `fcm_tokens/{uid}`.

## Firestore Rules

The app expects owner-only access for notification tokens:

```text
match /fcm_tokens/{userId} {
  allow read, write: if signedIn() && request.auth.uid == userId;
}
```

## Server Delivery

There is no Edge Function or webhook delivery path in the current codebase. Future notification delivery should use Firebase Admin SDK from Cloud Functions or another trusted server and read from `fcm_tokens`.

## Notes

- Notification opt-in is controlled in app settings and stored locally.
- If device permission is denied, the app keeps notifications off and surfaces that state in settings.
