import 'package:firebase_core/firebase_core.dart';

/// Supply platform-specific Firebase app values with --dart-define-from-file.
/// Empty configuration intentionally starts in guest mode without contacting Firebase.
class FirebaseConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static bool get configured =>
      [apiKey, appId, projectId, senderId].every((v) => v.isNotEmpty);
  static FirebaseOptions get options => const FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    projectId: projectId,
    messagingSenderId: senderId,
    authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
    iosBundleId: String.fromEnvironment(
      'FIREBASE_IOS_BUNDLE_ID',
      defaultValue: 'com.example.leafy',
    ),
  );
}
